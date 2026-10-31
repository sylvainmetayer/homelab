# Sauvegarde des bases KeePass (poste)

Les bases KeePass vivent dans un dossier synchronisé par kDrive
(`~/kDrive/keepass/*.kdbx`) : une suppression ou un écrasement s'y propage
partout. Le rôle `keepass_backup` des dotfiles en garde trois copies, toutes
hors de ce dossier et jamais écrasées (sauf la couche 0, une seule copie par
base) :

| Couche | Quoi | Où |
|---|---|---|
| 0 | KeePassXC copie la base avant chaque enregistrement (`BackupBeforeSave`) | `~/.local/share/keepass-backup/keepassxc/*.old.kdbx` |
| 1 | copie horodatée de chaque base modifiée (signature KDBX vérifiée), à chaque changement et chaque heure ; supprimée quand la date de modification **de la source**, qu'elle garde, a plus de 365 jours, sauf les deux plus récentes : une base intouchée depuis un an perd sa copie dès que deux copies plus récentes existent | `~/.local/share/keepass-backup/history/<base>/<base>.<AAAAMMJJTHHMMSS.ns>.kdbx` |
| 2 | snapshot restic horaire, tag `keepass`, clé writer sans droit de suppression | bucket OVH `keepass-backup-sylvain`, Object Lock 30 jours ([tofu/keepass_backup](../../tofu/keepass_backup/README.md)) |

Unités systemd **utilisateur** : `keepass-backup.path` déclenche
`keepass-backup-local.service` (couche 1) ; `keepass-backup-remote.timer`
(horaire) lance `keepass-backup-remote.service` (couches 1 et 2) ;
`keepass-backup-check.timer` (mensuel) lance `keepass-backup-check.service`
(`restic check`, restauration du dernier snapshot, comparaison avec la
source). Le pourquoi et les variables : [README du
rôle](https://github.com/sylvainmetayer/dotfiles/blob/main/roles/keepass_backup/README.md) ;
le bucket, les clés et leurs droits : [tofu/keepass_backup](../../tofu/keepass_backup/README.md).

Le script `~/.local/bin/keepass-backup` accepte `local`, `remote`, `run`
(`local` puis `remote`), `check` et `init`. Il lit lui-même
`~/.config/keepass-backup/env` et se place dans `/` : il se lance de
n'importe où. `restic` lancé à la main, lui, est un shim mise : depuis un
projet mise (ce dépôt par exemple), il chargerait l'environnement du projet
(clés `AWS_*` d'un autre bucket) par-dessus celui de la sauvegarde. Toujours
le lancer depuis `/` comme le script (seule la config mise globale
s'applique), dans un sous-shell qui charge le fichier env :

```bash
( cd / && set -a && . ~/.config/keepass-backup/env && set +a && restic snapshots )
```

Le sous-shell garde les clés S3 hors du shell courant.

## Première exécution

Après `ansible-playbook playbook/setup-home.yaml --tags keepass_backup`
(depuis les dotfiles, valeurs `keepass_backup_restic` remplies dans
`host_vars/home.sops.yaml` : [brancher le
poste](../../tofu/keepass_backup/README.md#brancher-le-poste)) :

```bash
systemctl --user list-timers 'keepass-backup*'      # remote (horaire) et check (mensuel)
systemctl --user status keepass-backup.path keepass-backup-remote.service --no-pager
keepass-backup init     # une fois : crée le dépôt restic (« already initialised » ensuite)
keepass-backup run      # premières copies locales et premier snapshot
keepass-backup check    # test de restauration : « check: restore test OK (N database(s) identical) »
( cd / && set -a && . ~/.config/keepass-backup/env && set +a && restic snapshots )
```

Puis **redémarrer KeePassXC** une fois : il ne lit `BackupBeforeSave` qu'au
démarrage. Après le prochain enregistrement d'une base, un `*.old.kdbx`
apparaît dans `~/.local/share/keepass-backup/keepassxc/`.

## Symptôme

- Notification de bureau critique « Sauvegarde KeePass en échec » :
  « `<unité>` a échoué : journalctl --user -u `<unité>` »
  (`keepass-backup-notify@.service`).
- Ou : `systemctl --user status keepass-backup-remote.service` en `failed`,
  ou en `activating (auto-restart)` (un échec réel est retenté toutes les
  10 minutes, le test mensuel toutes les heures).
- Ou : `restic snapshots` ne montre pas de snapshot récent alors que les bases
  ont changé.
- Ou : une base à récupérer (supprimée, écrasée par kDrive, corrompue) :
  [Restaurer une base](#restaurer-une-base).

## Diagnostic

```bash
journalctl --user -u keepass-backup-remote.service -n 100 --no-pager
journalctl --user -u keepass-backup-local.service -n 100 --no-pager
journalctl --user -u keepass-backup-check.service -n 100 --no-pager
systemctl --user list-timers 'keepass-backup*'
```

Hors ligne n'est pas un échec : `nm-online` (`ExecCondition`) attend le réseau
2 minutes puis saute le passage, sans notification ; le timer réessaie à
l'heure suivante.

| Message | Cause probable |
|---|---|
| `remote: restic not configured (empty or CHANGEME values), skipped` | **pas d'échec, mais pas de snapshot** : valeurs restic absentes ou `CHANGEME` dans le sops des dotfiles, fichier `restic-password` illisible, ou shim `~/.local/share/mise/shims/restic` absent (restic désinstallé de mise) |
| `check: restic not configured` / `init: restic not configured` | mêmes causes, mais `check` et `init` échouent |
| `source dir missing: …` | `~/kDrive/keepass` absent (kDrive non monté ou dossier renommé) |
| `history: <base> skipped, not a complete KDBX file` | fichier en cours d'écriture, ou qui n'est pas une base KDBX : sans gravité s'il est copié au passage suivant |
| `wrong password or no key found` | `password` du sops différent de celui du dépôt |
| `403` / `AccessDenied` sur `backup` | clé writer révoquée ou changée côté Tofu sans mettre à jour le sops ; une policy toute neuve peut mettre quelques minutes à s'appliquer |
| `repository is already locked` | un autre restic tourne, ou un verrou orphelin (le script attend déjà 10 minutes, `--retry-lock 10m`) |
| `check: MISSING in restore: …` | une base de la source absente du dernier snapshot (base créée depuis, snapshot en échec) |
| `check: CONTENT DIFFERS: …` | la base restaurée diffère de la source sans que la source soit plus récente : à prendre au sérieux |
| `check: no database could be compared with the restore` | toutes les bases ont changé depuis le dernier snapshot : lancer `keepass-backup run`, puis `keepass-backup check` |

`check: <base> changed after the snapshot, skipped` est normal : la base a
été modifiée après le dernier snapshot.

## Réparation

- **restic non configuré** : remplir `keepass_backup_restic` dans
  `host_vars/home.sops.yaml` des dotfiles (valeurs de `tofu output` :
  [brancher le poste](../../tofu/keepass_backup/README.md#brancher-le-poste)),
  installer restic par mise s'il manque, puis relancer
  `ansible-playbook playbook/setup-home.yaml --tags keepass_backup` et
  `keepass-backup run`.
- **kDrive absent** : remettre le client kDrive en route
  ([kdrive-nas.md](kdrive-nas.md) pour la copie côté NAS), puis
  `keepass-backup run`.
- **Verrou orphelin** (aucun restic en cours, `pgrep -a restic` vide) : la
  clé writer peut supprimer les seuls `locks/*` :

  ```bash
  ( cd / && set -a && . ~/.config/keepass-backup/env && set +a && restic unlock )
  ```

- **403** : comparer la clé du sops avec `mise exec -- tofu output -raw
  writer_access_key` dans `tofu/keepass_backup`, corriger le sops, relancer le
  playbook.
- **Mauvais mot de passe** : reprendre celui du papier (le dépôt n'a qu'un
  mot de passe), le remettre dans le sops, relancer le playbook.
- **`CONTENT DIFFERS`** : ne rien supprimer. Lancer `restic check` (sous-shell
  plus haut), garder les couches 0 et 1 telles quelles, ouvrir la base source
  et la base restaurée dans KeePassXC pour voir laquelle est saine.

Après la réparation, relancer l'unité nommée par la notification
(`keepass-backup-local.service`, sans `Restart=`, reste en `failed` jusqu'au
prochain changement de la source), puis effacer l'état `failed` :

```bash
systemctl --user restart <unité>
systemctl --user reset-failed 'keepass-backup*'
```

## Restaurer une base

Fermer la base dans KeePassXC (ou KeePassXC entier) avant de remplacer quoi
que ce soit dans `~/kDrive/keepass/`. Toujours ouvrir la copie choisie
**avant** de la remettre en place, et garder la base abîmée sous un autre nom
le temps de vérifier.

1. **Couche 0**, l'état avant le dernier enregistrement (une écriture ratée,
   une fusion fausse) : `~/.local/share/keepass-backup/keepassxc/*.old.kdbx`.
   Une seule copie par base, remplacée à chaque enregistrement : la mettre de
   côté tout de suite, avant de rouvrir la base.
2. **Couche 1**, l'historique (base supprimée ou écrasée par kDrive) :

   ```bash
   ls -lt ~/.local/share/keepass-backup/history/<base>/
   ```

   Le nom porte l'heure de la copie, la date de modification celle de la
   source. Ouvrir la copie choisie dans KeePassXC, puis la recopier dans
   `~/kDrive/keepass/<base>.kdbx`.
3. **Couche 2**, restic (poste perdu, historique local détruit) : restaurer
   dans un dossier temporaire du poste, hors du dossier synchronisé, que la
   flatpak KeePassXC peut lire :

   ```bash
   (
     cd / && set -a && . ~/.config/keepass-backup/env && set +a
     dest=$(mktemp -d ~/.local/share/keepass-backup/restore.XXXXXX)
     restic restore latest --host "$KEEPASS_BACKUP_RESTIC_HOST" --tag "$KEEPASS_BACKUP_RESTIC_TAG" --target "$dest"
     echo "restauré dans : $dest$KEEPASS_BACKUP_SOURCE_DIR"
     ls -l "$dest$KEEPASS_BACKUP_SOURCE_DIR"
   )
   ```

   Les fichiers sont restaurés sous leur chemin d'origine
   (`<dossier>/home/<utilisateur>/kDrive/keepass/`). Pour remonter plus loin,
   lister les snapshots (`restic snapshots --tag keepass`, sous-shell plus
   haut) et remplacer `latest` par l'id choisi. Ouvrir la base restaurée dans
   KeePassXC, la recopier dans `~/kDrive/keepass/`, puis supprimer le dossier
   `restore.*`.

   Sur un autre poste, sans le fichier env : la clé writer (lecture) est dans
   le sops des dotfiles, le mot de passe du dépôt sur papier, le dépôt dans
   `tofu output -raw restic_repository`. Sans clé age non plus :
   [perte-cle-ou-poste.md](perte-cle-ou-poste.md).

## Vérification

```bash
keepass-backup run
keepass-backup check      # « check: restore test OK (N database(s) identical) »
( cd / && set -a && . ~/.config/keepass-backup/env && set +a && restic snapshots --latest 1 )
systemctl --user list-timers 'keepass-backup*'
```

Le dernier snapshot a l'heure du `run`, les deux timers ont une prochaine
échéance, aucune unité `keepass-backup*` n'est en `failed`
(`systemctl --user --failed`). Après une restauration : la base s'ouvre avec
son mot de passe maître et contient les entrées attendues.

## Test trimestriel

Le test mensuel automatique compare des octets : il ne prouve ni que le
mot de passe papier ouvre le dépôt, ni que la base restaurée s'ouvre. Chaque
trimestre, le même jour que le [test de la clé `secours`](test-cle-secours.md),
dont le moniteur « Rotation des secrets » rappelle l'échéance et qui renvoie
ici :

1. Ouvrir le dépôt avec le **mot de passe papier** : sans fichier de mot de
   passe, restic le demande.

   ```bash
   ( cd / && set -a && . ~/.config/keepass-backup/env && set +a && unset RESTIC_PASSWORD_FILE && restic snapshots --latest 1 )
   ```

2. Restaurer le dernier snapshot comme en [couche 2](#restaurer-une-base),
   ouvrir chaque base restaurée dans KeePassXC, puis supprimer le dossier
   `restore.*`.
3. `keepass-backup check`.

## Rétention annuelle

Le poste n'oublie jamais rien : la clé writer ne peut pas supprimer de
snapshot. Une fois par an, avec la **clé admin** (entrée « Sauvegarde KeePass
/ restic OVH admin » de KeePassXC, jamais écrite sur le poste),
`restic forget --tag keepass --keep-within 1y --keep-monthly 24
--keep-yearly unlimited --prune`. Procédure complète et effet sur les
versions du bucket : [Rétention, une fois par an, avec la clé
admin](../../tofu/keepass_backup/README.md#rétention-une-fois-par-an-avec-la-clé-admin).

## Objet écrasé

Un objet du dépôt restic écrasé ou supprimé dans le bucket se récupère par
ses versions (bucket versionné, Object Lock 30 jours), avec la clé admin :
[Restaurer un objet
écrasé](../../tofu/keepass_backup/README.md#restaurer-un-objet-écrasé).

## Prévention

- Le test mensuel (`keepass-backup-check.timer`) et le test trimestriel
  ci-dessus.
- Le mot de passe du dépôt reste **sur papier** en plus du sops : pas
  seulement dans KeePassXC, qui est ce que ce dépôt sauvegarde.
- Ne pas désinstaller restic de mise (`mise_global_plugins` des dotfiles) :
  sans lui, `remote` saute le snapshot sans échouer.
- Une nouvelle base posée dans `~/kDrive/keepass/` est prise d'office
  (`*.kdbx`) ; une base rangée ailleurs n'est pas sauvegardée.
