# Add remote worker + remote machine learning

Source <https://github.com/immich-app/immich/discussions/15085#discussioncomment-13102618>

## Prérequis

- On immich server :
  - publish DB, redis ports on the LAN: they are on `127.0.0.1` only by
    default. From `ansible/`:
    `ansible-playbook pi.yml --tags immich -e immich_remote_worker=true -e immich_remote_worker_ip=<IP LAN du poste>`,
    and the same run without `-e` once the worker is done, to close them again
    (a merge that redeploys `immich` closes them too). Only that IP gets
    through (`DOCKER-USER`, `ansible/roles/immich/tasks/remote_worker.yml`);
    the rule is not persisted: after a Pi reboot, run it again with the same
    `-e`
  - (optional) disable worker with `IMMICH_WORKERS_INCLUDE=api` to only run API

- On remote host
  - `sshfs` + `docker`/`docker compose`
  - `user_allow_other` activé dans `/etc/fuse.conf`

## Steps

Adapt path to your setup.

```shell
mkdir -p ~/Documents/homelab/compose/immich/library
# Root ne se connecte plus au Pi (durcissement, lot 5) : sylvain, et le serveur
# SFTP lancé par sudo pour lire la bibliothèque de root.
sshfs sylvain@192.168.1.96:/opt/apps/immich/library ~/Documents/homelab/compose/immich/library -o allow_other,default_permissions,uid=$(id -u),gid=$(id -g) -o IdentityFile=/home/sylvain/.ssh/keepassxc.pub -o sftp_server="/usr/bin/sudo /usr/lib/openssh/sftp-server"
ls ~/Documents/homelab/compose/immich/library
# check files are there
cat ~/Documents/homelab/compose/immich/.env
# edit DB_HOSTNAME and REDIS_HOSTNAME to point to homelab IP; DB_PASSWORD and
# REDIS_PASSWORD (Valkey requires it) are those of the Pi's .env:
ssh sylvain@192.168.1.96 "grep -E '^(DB|REDIS)_PASSWORD=' /opt/apps/immich/.env"
docker compose -f compose/immich/compose.yaml up -d
docker logs -f immich_server_remote
```

In [immich settings](https://my.immich.app/admin/system-settings?isOpen=job), increase settings (ex: 50 thumbnails concurrently).

Let your remote worker run until all jobs are processed, then unmount the sshfs folder.

```shell
fusermount -u ~/Documents/homelab/compose/immich/library
```

Then close the Pi's DB and redis ports again, from
`ansible/`: `ansible-playbook pi.yml --tags immich`, without `-e`.

If you enabled `IMMICH_WORKERS_INCLUDE=api` on the server, don't forget to revert it back to default and restart the server compose so that the server can process jobs again.

## Versions alignées

`immich-server` et `immich-machine-learning` sont toujours à la même version,
ici comme dans le rôle `ansible/roles/immich` (le Pi) : le serveur et son
machine learning sortent ensemble à chaque release. Renovate les monte dans un
seul groupe (`immich-role-dependencies`), mais un groupe n'est pas atomique :
quand la recherche des tags d'une image échoue (ghcr.io pagine les plus de
200 000 tags d'`immich-machine-learning` par 1 000, une seule page en erreur et
le Dependency Dashboard affiche `no-result`), la PR part avec le serveur seul.
C'est arrivé avec #753 (serveur v3.3.3, machine learning resté en v3.3.1 six
jours).

Le workflow Lint l'arrête désormais : `.github/scripts/check_immich_versions.py`
échoue si les deux tags diffèrent dans un compose qui les cite (le digest,
propre à chaque image, et un suffixe d'accélération comme `-openvino` ne sont
pas comparés). Sur une PR Renovate qui y échoue, cocher « rebase/retry » pour
relancer la recherche, ne jamais merger une image seule ; une montée à la main
change les deux images dans les deux fichiers.
