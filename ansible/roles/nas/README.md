# nas

Réglages NFS du NAS Ugreen (UGOS Pro 1.20, Debian 12) : le rôle ne touche que
les fichiers que lit UGOS et ses propres exports, puis vérifie que le NAS est
conforme. Les dossiers partagés, comptes et droits se créent dans l'interface
d'UGOS, jamais ici. Joué par `ansible/nas.yml`, à la main (jamais en CI).

## Ce que fait le rôle

- `maximumNFSProtocol` dans `/etc/nfs.json` (`nas_nfs_max_protocol`, `NFSv3`) :
  `conf_tool` en régénère `/etc/nfs.conf` à chaque démarrage de `nfs-server`,
  une modification de `nfs.conf` à la main serait écrasée. Réécrit seulement si
  la valeur diffère (l'interface reformate le fichier à chaque enregistrement).
- Ses exports dans `/etc/exports.d/homelab.exports` (`nas_nfs_exports`, vide
  aujourd'hui), pas dans `/etc/exports` qui reste à UGOS. Chaque dossier doit
  exister (contrôle avant toute modification), les clients sont des IP, jamais
  un sous-réseau.
- Un contrôle de l'état de `nfs-server` et des exports actifs
  (`nas_manage_services: false` pour Molecule : pas de nfsd en conteneur).

## Sauvegarde de la configuration d'UGOS

Dépôt Borg `ugos_config` (sous-compte `nas`), par le gabarit partagé du rôle
`borgmatic`. Un drop-in de `borgmatic.service`
(`/etc/systemd/system/borgmatic.service.d/ugos-config.conf`, même schéma que
MediaManager) lance `/volume1/docker/ugos-config/stage.sh` avant
chaque passage : le script copie `/etc/exports`, `/etc/exports.d/*`,
`/etc/samba/smb.conf`, `/etc/samba/smbshare.conf`, `/etc/crontab` et
`/etc/ssh/sshd_config` dans `ugos-config/staging` (0700 root, fichiers 0600),
dossier sous `docker_base_path` que le conteneur borgmatic monte déjà (il ne
voit pas `/etc` de l'hôte). Le staging est vidé à chaque passage. Un fichier
absent (UGOS le déplace à une mise à jour) ou une copie ratée n'arrête rien :
la ligne « UGOS config : … absent » reste dans le journal de
`borgmatic.service`. Listes : `nas_ugos_config_files` / `_dirs`, coupure :
`nas_ugos_config_backup_enabled: false`. Un lien symbolique est copié comme
lien (`cp -P`), jamais sa cible.

Ni moniteur Uptime Kuma ni test de restauration (exclu dans
`check_restore_coverage.py`) : quelques Ko de texte sans base. Un échec de ce
dépôt fait échouer `borgmatic.service`, que signale la règle
`borgmatic-failed` de `log_alerts`.

Exclus volontairement : `smbpasswd`, `samba.json`, `smbglb.conf`, clés
d'hôte SSH, `/etc/shadow`. Non sauvegardés, faute de fichier : comptes, droits
et règles d'instantanés d'UGOS (base interne), configuration de la Bbox.

## Pourquoi NFSv3

UGOS n'exporte pas de pseudo-racine NFSv4 (`mountd : Cannot export /`), et la
seule racine possible, `/volume1`, exposerait `@home` et `@appstore`
([ADR 0007](../../../docs/adr/0007-donnees-sur-le-nas.md)).

## État

Le volet NFS de l'ADR 0007 n'est plus appliqué depuis le 2026-11-04 : aucune
appli ne garde ses données sur le NAS. Le rôle est gardé (décision de Sylvain),
voir aussi [nas_storage](../nas_storage/README.md). Les autres rôles du NAS ont
chacun leur README (`jellyfin`, `nas_proxy`, `kdrive_sync`, `mediamanager`).
