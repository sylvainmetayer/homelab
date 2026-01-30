# Add remote worker + remote machine learning

Source <https://github.com/immich-app/immich/discussions/15085#discussioncomment-13102618>

## Prérequis

- On immich server :
  - publish DB, redis ports
  - (optional) disable worker with `IMMICH_WORKERS_INCLUDE=api` to only run API

- On remote host
  - `sshfs` + `docker`/`docker compose`
  - `user_allow_other` activé dans `/etc/fuse.conf`

## Steps

Adapt path to your setup.

```shell
mkdir -p ~/Documents/homelab/compose/immich/library
sshfs root@192.168.1.96:/opt/apps/immich/library ~/Documents/homelab/compose/immich/library -o allow_other,default_permissions,uid=$(id -u),gid=$(id -g) -o IdentityFile=/home/sylvain/.ssh/keepassxc.pub
ls ~/Documents/homelab/compose/immich/library
# check files are there
cat ~/Documents/homelab/compose/immich/.env
# edit DB_HOSTNAME and REDIS_HOSTNAME to point to homelab IP, update passwords if needed
docker compose -f compose/immich/compose.yaml up -d
docker logs -f immich_server_remote
```

In [immich settings](https://my.immich.app/admin/system-settings?isOpen=job), increase settings (ex: 50 thumbnails concurrently).

Let your remote worker run until all jobs are processed, then unmount the sshfs folder.

```shell
fusermount -u ~/Documents/homelab/compose/immich/library
```

If you enabled `IMMICH_WORKERS_INCLUDE=api` on the server, don't forget to revert it back to default and restart the server compose so that the server can process jobs again.
