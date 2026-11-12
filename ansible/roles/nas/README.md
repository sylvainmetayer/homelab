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

## SSH par clé seulement (tag `nas_ssh`)

`tasks/ssh.yml`, en dernier du rôle : le fichier
`/etc/ssh/sshd_config.d/10-homelab-key-only.conf` (`nas_ssh_dropin`) pose
`PasswordAuthentication no` et `KbdInteractiveAuthentication no`, rien d'autre
(`PermitRootLogin no` est déjà celui d'UGOS ; le reste de `sshd_config`
appartient à UGOS). Ce n'est pas le rôle `security` : le NAS n'en dépend pas
(pas de fail2ban, de ufw ni de devsec), et sa liste d'algorithmes n'est pas
durcie. Garde-fous, dans cet ordre :

1. une clé (ed25519, RSA, ECDSA, sk) doit exister dans
   `~<nas_ssh_user>/.ssh/authorized_keys` (l'utilisateur d'Ansible) : sinon le
   rôle échoue **avant** d'écrire (un `AuthorizedKeysFile` non standard fait
   aussi échouer ce contrôle : l'adapter, ou le mesurer d'abord) ;
2. le fichier est validé seul (`sshd -t -f`), puis la configuration entière
   (`sshd -t`) ;
3. `systemctl reload` (`nas_ssh_service`, `ssh`), jamais restart : les sessions
   ouvertes restent ;
4. `sshd -T` doit dire `passwordauthentication no`,
   `kbdinteractiveauthentication no`, `pubkeyauthentication yes` (il lit les
   fichiers : il prouve que le fichier est inclus et gagne) ; une connexion
   `ssh` sans clé vers 127.0.0.1 ne doit proposer que `(publickey)` (cela
   prouve le démon vivant) ; une connexion Ansible neuve (`reset_connection`,
   `ping`) doit passer ;
5. si l'une de ces vérifications échoue après l'écriture : le fichier d'avant
   est remis (ou supprimé s'il n'existait pas), sshd rechargé, le play échoue.

Le retour arrière d'Ansible suppose une connexion qui marche encore ; si c'est
la connexion neuve qui est coupée (hôte « unreachable », rien ne tourne plus),
il faut la main : depuis **la session ssh gardée ouverte pendant le déploiement**,
`sudo rm /etc/ssh/sshd_config.d/10-homelab-key-only.conf && sudo systemctl reload ssh`.

`nas_ssh_key_only: false` saute ces tâches mais ne défait rien. Les mises à
jour d'UGOS peuvent réécrire `/etc/ssh` ou l'overlay : refaire
`ansible-playbook nas.yml --tags nas_ssh` (idempotent) et relire
`sudo sshd -T | grep -E '^(passwordauth|kbdinteractive)'`. Aucun contrôle
automatique n'alerte encore si les mots de passe reviennent (à faire : push
Uptime Kuma hebdomadaire, moniteur dans `tofu/pangolin_config`).

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
