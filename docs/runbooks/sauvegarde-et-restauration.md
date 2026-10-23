# Sauvegarde en échec, restauration d'une appli depuis Borg

Rappels : borgmatic tourne en **root** (`/root/.local/bin/borgmatic`), une
config par appli dans `/etc/borgmatic.d/<app>.yaml`, lancées toutes ensemble
par `borgmatic.timer` à 01:00. Chaque hôte parle à **son** sous-compte de la
Storage Box (`backup-<hôte>`, port 23, clé
`/root/.ssh/borgmatic_storage_box_ed25519`, alias SSH `backup_storage_box`
dans `/root/.ssh/config`).

## Symptôme

- Le moniteur push de sauvegarde de l'appli (groupe Backups d'Uptime Kuma)
  passe DOWN : le run a signalé un échec, ou aucun push depuis 24 h
  (`uptimekuma_monitor_push.backup`, `tofu/pangolin_config/websites.tf`).
- Ou : `borgmatic.service` en `failed` sur l'hôte.
- Ou : des données à récupérer (fausse manipulation, base corrompue).

## Diagnostic

Sur l'hôte de l'appli (exemple : `rss` sur la VM docker).

```bash
systemctl status borgmatic.timer borgmatic.service
sudo journalctl -u borgmatic.service -n 300 --no-pager
```

Ne pas lancer `journalctl --since -30days` sur la VM docker : lire tout le
journal sur son disque rotatif fait monter la charge à plus de 30.

Erreurs courantes :

| Message | Cause probable |
|---|---|
| `Permission denied (publickey)` | la clé de root n'est pas autorisée chez le sous-compte (hôte neuf ou reconstruit) |
| `Host key verification failed` | clé d'hôte de la Storage Box absente de `/root/.ssh/known_hosts` |
| `Failed to create/acquire the lock` | un run précédent interrompu a laissé un verrou |
| erreur de `mariadb-dump` / `pg_dump` | conteneur de la base arrêté ou renommé |
| erreur `sqlite3` | base SQLite déplacée ou supprimée depuis le déploiement |
| `passphrase supplied … is incorrect` | `backup_passphrase` changée dans SOPS sans migrer les dépôts |

Tester à la main :

```bash
sudo ssh backup_storage_box ls                      # le sous-compte répond-il ?
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml list
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml --verbosity 1   # un run complet de cette appli
```

## Réparation

- **Clé non autorisée** (hôte neuf ou reconstruit) : l'ordre de
  `ansible/backup.yaml`.

  ```bash
  cd ansible
  ansible-playbook <playbook de l'hôte> --tags setup   # le rôle borgmatic génère la clé
  ansible-playbook backup.yaml                          # l'autorise chez le sous-compte
  ansible-playbook <playbook de l'hôte>                 # repo-create et configs borgmatic
  ```

- **Verrou orphelin** (aucun borgmatic en cours, `pgrep -a borg` vide) :

  ```bash
  sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml break-lock
  ```

- **Dump en échec** : remettre la base en route
  ([appli-en-panne.md](appli-en-panne.md)), puis relancer un run.
- **Config borgmatic fausse ou périmée** : redéployer la partie sauvegarde
  du rôle : `ansible-playbook docker.yml --tags backup`.

## Restaurer une appli

La procédure pas à pas (arrêt, `borgmatic extract`, copie, `borgmatic
restore` des dumps SQL, cas SQLite) est dans
[../backup-restore.md](../backup-restore.md). Les points à ne pas rater :

1. **Arrêter l'appli** avant : `systemctl --user stop dc@rss` (Pangolin :
   `sudo systemctl stop pangolin`).
2. **Choisir l'archive** : `borgmatic list` montre les archives
   `<app>-<date>` ; `--archive latest` prend la dernière.
3. **Extraire dans un dossier de travail**, jamais directement sur `/` :
   `--destination /root/restore/<app>`. Les chemins n'ont pas de `/`
   initial.
4. **Bases PostgreSQL / MariaDB** : l'appli et son conteneur de base
   démarrés, `borgmatic restore --config /etc/borgmatic.d/<app>.yaml
   --archive latest`.
5. **Bases SQLite** : la copie est dans l'archive sous
   `var/lib/borgmatic-sqlite/<app>/`, nommée d'après son chemin d'origine
   (`/` remplacés par `_`). Appli arrêtée, la remettre en place, puis lui
   rendre son propriétaire (`stat -c %u:%g` sur l'ancienne avant, `chown`
   après ; `borgmatic/defaults/main.yml`).
6. **Dépôt lui-même effacé ou abîmé** : les snapshots de la Storage Box
   (9 quotidiens, `tofu/pangolin/storage_box.tf`) se restaurent depuis la
   console Hetzner (Storage Box → Snapshots), avec le compte principal.
   Procédure exacte : à vérifier dans la console.

## Vérification

```bash
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml --verbosity 1
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml list --last 1
```

Le moniteur push repasse UP. Après une restauration : l'appli répond, et ses
données sont celles attendues.

## Prévention

- Une restauration d'essai de temps en temps, sur une petite appli
  (`betisier`) : c'est le seul vrai test d'une sauvegarde.
- Garder `backup_passphrase` hors du seul SOPS (gestionnaire de mots de
  passe) : sans elle, aucun dépôt ne s'ouvre.
- borgmatic vérifie le dépôt toutes les 2 semaines et les archives tous les
  mois (`checks:` du modèle `app.yaml.j2`).
