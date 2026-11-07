# Copie de kDrive vers le NAS

kDrive reçoit les envois du téléphone ; le NAS en garde une deuxième copie,
mise à jour chaque nuit par le rôle `kdrive_sync` (`ansible/nas.yml`, à la
main seulement). Sens unique, sans suppression :

- `rclone copy`, jamais `sync` : un fichier supprimé dans kDrive, par erreur
  ou par un rançongiciel, **reste** sur le NAS.
- Un fichier *remplacé* dans kDrive (modifié, ou chiffré sur place) dont la
  taille change est recopié, et sa version précédente est **déplacée**, pas
  écrasée, dans `versions/<date et heure du passage>/` (`--backup-dir`). À
  taille égale, il n'est pas recopié (plus bas).
- Rien n'efface jamais rien côté NAS : `versions/` ne fait que grossir, son
  ménage est manuel (plus bas).
- Hors copie (`kdrive_sync_exclude_patterns`, `host_vars/nas`) : `Videos/`,
  `Backups/Synology/tv/` et `movies/` (films et séries, 1,27 To au relevé du
  16/10) et les corbeilles digiKam `.dtrash/`. Ces films n'ont donc pas de
  copie sur le NAS par ce rôle. Le reste fait environ 0,95 To. Une exclusion
  ne vaut que pour les passages à venir : ce qui est déjà dans `miroir/` y
  reste.

| Quoi | Où |
|---|---|
| Miroir de kDrive | `/volume1/kdrive/miroir/` |
| Versions remplacées | `/volume1/kdrive/versions/AAAA-MM-JJTHHMMSS/` |
| Compose (mot de passe d'application) | `/volume1/docker/kdrive_sync/compose.yaml`, 0600 root |
| Script (statistiques, push) | `/volume1/docker/kdrive_sync/kdrive_sync.py` |
| Unités | `kdrive-sync.service` (oneshot), `kdrive-sync.timer` (04:00, `Persistent`) |
| Moniteur | « kDrive vers NAS » (`tofu/pangolin_config/cron_kdrive_sync.tf`), rouge sur un échec ou après 49 h sans nouvelles |

rclone parle WebDAV (`https://<id>.connect.kdrive.infomaniak.com`, [doc
Infomaniak](https://www.infomaniak.com/fr/support/faq/2636)) : il n'a pas de
backend kDrive, et le jeton API de `kdvc` (kdrive-version-cleaner) n'ouvre
pas WebDAV. Il ne compare que les tailles : en WebDAV « other », rclone ne
lit ni date de modification ni somme de contrôle ([doc
rclone](https://rclone.org/webdav/)). Un fichier modifié dans kDrive **à
taille égale** n'est pas recopié : le miroir garde l'ancien contenu, rien ne
part dans `versions/`.

## Mise en place (une fois)

1. **Dossier partagé** : UGOS, Fichiers, Dossier partagé, Créer, `kdrive` sur
   le volume 1, lecture/écriture pour `sylvain`. Régler ses **instantanés**
   (Btrfs) comme dans « Protection » plus bas : ils protègent même d'un root du
   NAS compromis, ce que la copie seule ne fait pas.
2. **Mot de passe d'application** : Manager Infomaniak, profil, « Mots de
   passe d'application » ([doc](https://www.infomaniak.com/fr/support/faq/2855)),
   nommé `nas-kdrive-sync`. Jamais le mot de passe du compte. Il ouvre tout le
   compte en écriture (WebDAV ne connaît pas de lecture seule) : il ne vit que
   dans SOPS et dans le compose 0600 du NAS.
3. **Id du kDrive** : le nombre de l'URL de l'appli web,
   `kdrive.infomaniak.com/app/drive/<id>/…`.
4. **SOPS** (`secrets/ansible.sops.yaml`), depuis `ansible/` ; rien ne passe
   sur une ligne de commande ni dans l'historique du shell :

   ```sh
   read -r KDRIVE_ID && printf '%s' "$KDRIVE_ID" | jq -Rs . | sops set --value-stdin ../secrets/ansible.sops.yaml '["kdrive_drive_id"]'
   read -r KDRIVE_USER && printf '%s' "$KDRIVE_USER" | jq -Rs . | sops set --value-stdin ../secrets/ansible.sops.yaml '["kdrive_webdav_user"]'
   read -rs KDRIVE_PW && printf '%s' "$KDRIVE_PW" | jq -Rs . | sops set --value-stdin ../secrets/ansible.sops.yaml '["kdrive_webdav_app_password"]'
   unset KDRIVE_ID KDRIVE_USER KDRIVE_PW
   ```

   `kdrive_webdav_user` est l'e-mail de connexion du compte Infomaniak.
5. **Moniteur** : `tofu apply` dans `tofu/pangolin_config` (crée « kDrive
   vers NAS » et la sortie `uptime_cron_kdrive_sync_url` que lit `nas.yml`).
6. **Déploiement** : le dépôt porte `kdrive_sync_timer_enabled: true`
   (`host_vars/nas`). Sur une nouvelle installation, le passer d'abord à
   `false`, dans ce fichier : sinon le timer part dès le déploiement et la copie
   de 04:00 échappe aux contrôles du premier passage ; ne supprimant jamais
   rien, ce qu'elle rapatrierait à tort (corbeille, dossier inattendu) resterait
   sur le NAS. Puis `ansible-playbook nas.yml --tags kdrive_sync`. Le rôle refuse
   de déployer sans le dossier partagé ou les clés SOPS, et ne lance aucune
   copie. Faire ensuite le premier passage ci-dessous.

## Premier passage

Sur le NAS, en root. D'abord un essai, sans rien écrire :

```sh
cd /volume1/docker/kdrive_sync
docker compose run --rm --no-TTY rclone --dry-run > /root/kdrive-essai.log 2>&1
# Code de sortie : 0 attendu. Sinon l'essai n'a pas tout vu et les contrôles
# suivants ne valent rien : lire les erreurs du journal (« Échecs fréquents »).
echo $?
# Volume à copier, en octets : environ 0,95 To. Bien plus : une exclusion ne
# prend pas (motif ancré à la racine WebDAV, sensible à la casse).
grep -o '"totalBytes":[0-9]*' /root/kdrive-essai.log | tail -1
# Entrées de la racine telle que WebDAV la montre : corbeille et anciennes
# versions ne doivent pas y être (sinon, kdrive_sync_exclude_patterns).
grep -o '"object":"[^/"]*' /root/kdrive-essai.log | sort | uniq -c
# Chemins des exclusions dans l'essai, casse ignorée (les motifs, eux, y sont
# sensibles) : 0 attendu. Sinon, regarder lesquels, même commande sans -c
# (motif à corriger, ou dossier homonyme plus bas) avant toute copie.
grep -ciE '"object":"([^"]*/)?(Videos|Backups/Synology/(tv|movies)|\.dtrash)/' /root/kdrive-essai.log
```

Tout est bon : `rm /root/kdrive-essai.log`, qui liste tous les noms de
fichiers.

(L'entrée du conteneur est toujours `rclone copy … "$@"` : les arguments
s'ajoutent à la copie, d'où `--dry-run`.) Puis la vraie copie, en arrière-plan
(elle dure des heures) :

```sh
systemctl start --no-block kdrive-sync.service
journalctl -fu kdrive-sync.service
```

Bornée à 23 h (`kdrive_sync_timeout`) : une copie plus longue est arrêtée
(conteneur retiré, moniteur poussé en rouge) et reprend là où elle en était au
passage suivant : la nuit suivante si le timer est actif, sinon à relancer à
la main comme ci-dessus. Pour une première copie d'une traite, `--bwlimit` reste
vide par défaut ; à régler (`kdrive_sync_bwlimit`, par exemple
`"08:00,10M 23:00,off"`) si elle gêne la connexion de la maison.

Une fois la première copie terminée et vérifiée (moniteur vert, `du -s --si
/volume1/kdrive/miroir` proche de la taille du kDrive, exclusions déduites),
activer les passages nocturnes : remettre `kdrive_sync_timer_enabled: true` dans
`host_vars/nas`, puis `ansible-playbook nas.yml --tags kdrive_sync`.

Les dossiers `miroir/` et `versions/` sont à `sylvain`, en 0700 : seul ce
compte les lit par SMB. Un autre compte du NAS (famille, médias) n'y a pas
accès, volontairement.

## Retrouver un fichier

- Supprimé dans kDrive : il est toujours dans `miroir/`, ou dans
  `versions/<date>-avant-reorganisation/` si le miroir a été mis de côté depuis
  (plus bas).
- Remplacé ou chiffré dans kDrive : la version d'avant est dans le dossier
  `versions/` du passage qui l'a remplacé (le plus ancien qui le contient
  pour remonter loin). `find /volume1/kdrive/versions -path '*/<nom>'`.
- Après un rançongiciel dans kDrive : `miroir/` porte les fichiers chiffrés,
  `versions/<passage>/` les originaux. Avant tout, désactiver le timer
  (`systemctl disable --now kdrive-sync.timer`) pour figer la copie, et passer
  `kdrive_sync_timer_enabled: false` dans `host_vars/nas` tant qu'elle doit le
  rester : le prochain `nas.yml` rallumerait le timer, et `Persistent` lancerait
  aussitôt la copie manquée. Préférer le retour arrière de kDrive (jusqu'à
  3 mois) s'il suffit.
- Hors copie (`Videos/`, `Backups/Synology/tv/` et `movies/`, `.dtrash/`) :
  rien sur le NAS, ni miroir ni versions. Seul kDrive (corbeille, retour
  arrière) peut le rendre.

## Fichiers déplacés dans kDrive

`rclone copy` ne suit pas les déplacements : un fichier déplacé ou renommé dans
kDrive est recopié au nouveau chemin et reste à l'ancien dans `miroir/`. Après
une grosse réorganisation, repartir d'un miroir propre, sans rien effacer :
`miroir/` est la seule copie de ce qui a été supprimé dans kDrive. Le mettre de
côté dans `versions/`, puis tout recopier ; il faut la taille du miroir en plus
sur le volume (`df -h /volume1`) :

```sh
systemctl disable --now kdrive-sync.timer
systemctl stop kdrive-sync.service
mv /volume1/kdrive/miroir "/volume1/kdrive/versions/$(date +%Y-%m-%dT%H%M%S)-avant-reorganisation"
install -d -o sylvain -g "$(id -g sylvain)" -m 0700 /volume1/kdrive/miroir
systemctl start --no-block kdrive-sync.service
```

Une fois la copie terminée et vérifiée (comme au premier passage),
`systemctl enable --now kdrive-sync.timer` (jusque-là, pas de `nas.yml` : il
rallumerait le timer). L'ancien miroir suit ensuite le ménage de `versions/`.

## Ménage de `versions/`

Jamais automatique. Une fois les fichiers vérifiés, supprimer les dossiers
datés devenus inutiles, à la main (`du -sh /volume1/kdrive/versions/*`).

## Protection : pas de Borg, des instantanés

Décision du 07/11 : **pas de sauvegarde Borg de kDrive**. Elle ne tient pas
sur la Storage Box (~49 % d'1 Tio, pour ~0,95 To de miroir, versions du NAS en
plus). La protection est :

1. kDrive lui-même (versions, corbeille, retour arrière jusqu'à 3 mois) ;
2. le miroir `miroir/` + `versions/` sur le NAS (plus haut) ;
3. des **instantanés Btrfs d'UGOS** sur le dossier partagé `kdrive`, qui
   protègent même d'un root du NAS compromis ou d'une suppression à la main.

`kdrive_sync_backup_enabled` reste à `false`. Les instantanés ne sont pas dans
le dépôt : UGOS les règle dans son interface, puis on les relit de temps en
temps.

**Réglage en place** (relevé le 2026-11-07) : un instantané par jour à 00:00
du dossier partagé `kdrive`, gardé 14 jours, depuis le 2026-11-04. Ils sont
visibles sur le NAS par `btrfs subvolume list -s /volume1`
(`@snapshot/share_folder/kdrive/`). Celui de 00:00 contient la copie de 04:00
de la nuit d'avant.

### Régler les instantanés (UGOS)

Les menus changent d'une version d'UGOS à l'autre : les noms ci-dessous sont
à vérifier à l'écran.

1. Ouvrir, selon la version, le « Gestionnaire de stockage » puis les
   « instantanés » (ou l'équivalent), et choisir le dossier partagé `kdrive`
   du volume 1.
2. Créer une planification d'instantanés de ce seul dossier. Un point de
   départ à ajuster : un par jour, après la copie de 04:00 (par exemple
   06:00), gardés quelques semaines.
3. Fixer la rétention. Les instantanés prennent de la place quand `versions/`
   et `miroir/` changent : surveiller `df -h /volume1` après les premières
   semaines.
4. Vérifier : un instantané apparaît le lendemain, et un fichier d'essai
   supprimé dans `miroir/` se récupère depuis lui. Noter ici la fréquence et
   la rétention réellement choisies (le dépôt ne les connaît pas).

### Angles morts

- **Même maison** : le NAS et ses instantanés sont chez Sylvain. Incendie,
  vol ou surtension perdent le miroir et ses instantanés d'un coup.
- **Perte simultanée** : si kDrive est perdu (compte fermé, compromis) *et*
  le NAS en même temps, il ne reste rien. Le cas est peu probable, mais
  aucune troisième copie n'existe.
- Les instantanés sont sur les mêmes disques que le miroir : une panne des
  deux disques emporte les deux ([disque-nas-mort.md](disque-nas-mort.md)).
- Films et `Videos/` sont hors miroir (plus haut) : kDrive seul les garde.
- Si un jour une troisième copie est voulue : Borg exige de la place sur la
  Storage Box (`/volume1/kdrive` dans `borgmatic_container_source_paths`,
  moniteur « Backup », `kdrive_sync_backup_healthcheck_url`), ou un autre
  stockage distant.

## Échecs fréquents

| Message (moniteur, `journalctl -u kdrive-sync`) | Cause |
|---|---|
| `401 Unauthorized` | mot de passe d'application révoqué ou faux, ou `kdrive_webdav_user` n'est pas l'e-mail du compte |
| `404` sur la racine | `kdrive_drive_id` faux |
| `couldn't decrypt password` | la valeur n'est pas passée par `rclone obscure` (entrée du compose modifiée à la main) |
| `permission denied` sous `/data` | droits du dossier partagé `kdrive` retirés à `sylvain` dans UGOS |
