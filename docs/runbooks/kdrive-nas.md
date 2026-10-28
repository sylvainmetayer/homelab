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
   le volume 1, lecture/écriture pour `sylvain`. Activer ses **instantanés**
   (Btrfs) : ils protègent même d'un root du NAS compromis, ce que la copie
   seule ne fait pas.
2. **Mot de passe d'application** : Manager Infomaniak, profil, « Mots de
   passe d'application » ([doc](https://www.infomaniak.com/fr/support/faq/2855)),
   nommé `nas-kdrive-sync`. Jamais le mot de passe du compte. Il ouvre tout le
   compte en écriture (WebDAV ne connaît pas de lecture seule) : il ne vit que
   dans SOPS et dans le compose 0600 du NAS.
3. **Id du kDrive** : le nombre de l'URL de l'appli web,
   `kdrive.infomaniak.com/app/drive/<id>/…`.
4. **SOPS** (`ansible/secrets.sops.yaml`), depuis `ansible/` ; rien ne passe
   sur une ligne de commande ni dans l'historique du shell :

   ```sh
   read -r KDRIVE_ID && printf '%s' "$KDRIVE_ID" | jq -Rs . | sops set --value-stdin secrets.sops.yaml '["kdrive_drive_id"]'
   read -r KDRIVE_USER && printf '%s' "$KDRIVE_USER" | jq -Rs . | sops set --value-stdin secrets.sops.yaml '["kdrive_webdav_user"]'
   read -rs KDRIVE_PW && printf '%s' "$KDRIVE_PW" | jq -Rs . | sops set --value-stdin secrets.sops.yaml '["kdrive_webdav_app_password"]'
   unset KDRIVE_ID KDRIVE_USER KDRIVE_PW
   ```

   `kdrive_webdav_user` est l'e-mail de connexion du compte Infomaniak.
5. **Moniteur** : `tofu apply` dans `tofu/pangolin_config` (crée « kDrive
   vers NAS » et la sortie `uptime_cron_kdrive_sync_url` que lit `nas.yml`).
6. **Déploiement** : `ansible-playbook nas.yml --tags kdrive_sync`. Le rôle
   refuse de déployer sans le dossier partagé ou les clés SOPS. Il ne lance
   aucune copie et laisse le timer **coupé** (`kdrive_sync_timer_enabled:
   false`, `host_vars/nas`) : la copie ne supprimant jamais rien, ce qu'un
   premier passage automatique rapatrierait à tort (corbeille, dossier
   inattendu) resterait sur le NAS. Faire d'abord le premier passage
   ci-dessous.

## Premier passage

Sur le NAS, en root. D'abord un essai, sans rien écrire :

```sh
cd /volume1/docker/kdrive_sync
# Racine du kDrive telle que WebDAV la montre : corbeille et anciennes
# versions ne doivent pas y être (sinon, kdrive_sync_exclude_patterns).
docker compose run --rm --no-TTY rclone --dry-run --max-depth 1 2>&1 | tail -20
```

(L'entrée du conteneur est toujours `rclone copy … "$@"` : les arguments
s'ajoutent à la copie, d'où `--dry-run`.) Puis la vraie copie, en arrière-plan
(elle dure des heures) :

```sh
systemctl start --no-block kdrive-sync.service
journalctl -fu kdrive-sync.service
```

Bornée à 23 h (`kdrive_sync_timeout`) : une copie plus longue est arrêtée
(conteneur retiré, moniteur poussé en rouge) et reprend la nuit suivante, là
où elle en était. Pour une première copie d'une traite, `--bwlimit` reste
vide par défaut ; à régler (`kdrive_sync_bwlimit`, par exemple
`"08:00,10M 23:00,off"`) si elle gêne la connexion de la maison.

Une fois la première copie terminée et vérifiée (moniteur vert, `du -sh
/volume1/kdrive/miroir` proche de la taille du kDrive), activer les passages
nocturnes : `kdrive_sync_timer_enabled: true` dans `host_vars/nas`, puis
`ansible-playbook nas.yml --tags kdrive_sync`.

Les dossiers `miroir/` et `versions/` sont à `sylvain`, en 0700 : seul ce
compte les lit par SMB. Un autre compte du NAS (famille, médias) n'y a pas
accès, volontairement.

## Retrouver un fichier

- Supprimé dans kDrive : il est toujours dans `miroir/`.
- Remplacé ou chiffré dans kDrive : la version d'avant est dans le dossier
  `versions/` du passage qui l'a remplacé (le plus ancien qui le contient
  pour remonter loin). `find /volume1/kdrive/versions -path '*/<nom>'`.
- Après un rançongiciel dans kDrive : `miroir/` porte les fichiers chiffrés,
  `versions/<passage>/` les originaux. Avant tout, désactiver le timer
  (`systemctl disable --now kdrive-sync.timer`) pour figer la copie, et
  préférer le retour arrière de kDrive (jusqu'à 3 mois) s'il suffit.

## Ménage de `versions/`

Jamais automatique. Une fois les fichiers vérifiés, supprimer les dossiers
datés devenus inutiles, à la main (`du -sh /volume1/kdrive/versions/*`).

## Sauvegarde borg

Désactivée (`kdrive_sync_backup_enabled: false`) : le NAS est la deuxième
copie, kDrive garde son propre historique (versions, corbeille, retour
arrière), et la Storage Box (~49 % d'1 Tio) devrait recevoir toute la taille
du kDrive, versions du NAS comprises. Pour l'activer : ajouter
`/volume1/kdrive` à `borgmatic_container_source_paths` (`host_vars/nas`, ce
que le rôle vérifie), déclarer un moniteur « Backup » dans
`tofu/pangolin_config` et son URL dans `nas.yml`
(`kdrive_sync_backup_healthcheck_url`), puis vérifier la place restante.

## Échecs fréquents

| Message (moniteur, `journalctl -u kdrive-sync`) | Cause |
|---|---|
| `401 Unauthorized` | mot de passe d'application révoqué ou faux, ou `kdrive_webdav_user` n'est pas l'e-mail du compte |
| `404` sur la racine | `kdrive_drive_id` faux |
| `couldn't decrypt password` | la valeur n'est pas passée par `rclone obscure` (entrée du compose modifiée à la main) |
| `permission denied` sous `/data` | droits du dossier partagé `kdrive` retirés à `sylvain` dans UGOS |
