# Backup and restore

## How backups run

The `borgmatic` role installs Borg and Borgmatic for root, and a `borgmatic.timer` that runs every night at 01:00. Each app role adds its own config, `/etc/borgmatic.d/<app>.yaml`, rendered from the shared template `ansible/roles/borgmatic/templates/app.yaml.j2`. Each app gets its own Borg repository on the Hetzner Storage Box, through the Storage Box subaccount of its host: `ssh://<subaccount>@<server>/./<app>` (port 23, key `/root/.ssh/borgmatic_storage_box_ed25519`, generated on the host), i.e. `backup/<host>/<app>` seen from the main account. A subaccount only sees its own host's folder, and the Storage Box keeps 9 daily snapshots that no subaccount can delete.

The NAS (Jellyfin) is the exception: nothing is installed under UGOS, borgmatic runs in its official container at 02:30, with its configs, key and wrapper under `/volume1/docker/borgmatic` ([runbooks/sauvegarde-et-restauration.md](runbooks/sauvegarde-et-restauration.md) gives the paths to use instead of the ones below).

An archive holds:

- the app's files, usually its `compose.yaml` and data folders under `/opt/apps/<app>`;
- a dump of each PostgreSQL or MariaDB database, made by the client inside the database container;
- a copy of each SQLite database, made with `sqlite3` (`VACUUM INTO` for a WAL database, `.backup` otherwise) into `/var/lib/borgmatic-sqlite/<app>/` before the run. The live SQLite file is excluded.

Borg keeps 7 daily, 4 weekly, 6 monthly and 1 yearly archives. When the app has a backup healthcheck URL, each run pushes to its Uptime Kuma monitor, which alerts when a night is missed.

[ansible/roles/borgmatic/README.md](../ansible/roles/borgmatic/README.md) lists the rules the template follows. The `borgmatic-backup` skill wires a new app.

## Restore an app

The example uses `betisier` on the Docker VM. Replace it with the app name, which is also the name of its config file and of its folder under `/opt/apps`.

1. Stop the app. Apps run as systemd user units of `sylvain`:

   ```bash
   systemctl --user stop dc@betisier
   ```

2. As root, pick an archive and extract it to a scratch folder:

   ```bash
   sudo -i
   borgmatic=/root/.local/bin/borgmatic
   config=/etc/borgmatic.d/betisier.yaml
   $borgmatic list --config $config
   mkdir -p /root/restore/betisier
   $borgmatic extract --config $config --archive latest --destination /root/restore/betisier
   ```

   Use an archive name from the list in place of `latest` to go back further. Paths in the archive have no leading slash, so the app's files end up in `/root/restore/betisier/opt/apps/betisier/`. Borgmatic 2.1 also stores in the archive, outside the app's sources, its SQL dumps (`/root/restore/betisier/borgmatic/postgresql_databases/<container>:<port>/<database>`, `pg_restore` custom format, and the `mysql_databases` equivalent) and every `etc/borgmatic.d/*.yaml` of the host (for `borgmatic config bootstrap`).

3. Look at what came out, then copy it back over the app folder:

   ```bash
   cp -a /root/restore/betisier/opt/apps/betisier/. /opt/apps/betisier/
   ```

4. As `sylvain`, in a second terminal (keep the root shell of step 2 open: step 5 uses its `$borgmatic` and `$config`), start the database container alone (the app itself stays stopped, or it would write to the database or run its migrations while the dump is loaded), and wait for it to be healthy:

   ```bash
   cd /opt/apps/betisier
   docker compose up -d betisier_db
   docker compose ps betisier_db
   ```

5. As root, restore the database dumps. Borgmatic reaches the database container by its IP (`container:` in the config) and loads the dump with the host's client: `pg_restore` (17.11 on the Docker VM, which reads PostgreSQL 18.6 dumps) or `mysql` (borgmatic's default `mysql_command`, from `mariadb-client`). Should the host's `pg_restore` ever reject a newer dump, load the extracted one with the container's client instead ([runbooks/healthlog.md](runbooks/healthlog.md#restauration-depuis-borg)):

   ```bash
   $borgmatic restore --config $config --archive latest
   ```

   `--container <name>` restores into another container instead, for a drill against a throwaway database that leaves the app untouched ([runbooks/sauvegarde-et-restauration.md](runbooks/sauvegarde-et-restauration.md#restauration-dessai-sans-toucher-a-lappli)).

6. As `sylvain`, stop the database container started by hand, then start the whole app through its unit:

   ```bash
   docker compose stop && systemctl --user start dc@betisier
   ```

7. Remove `/root/restore/betisier` once the app works.

### SQLite apps

For an app whose data is SQLite (Pangolin, for example), there are no steps 4 and 5 (no database container, no dump): the app stays stopped until its unit starts it in step 6. The copy is in the extracted archive under `var/lib/borgmatic-sqlite/<app>/`, named after its original path with the slashes turned into underscores: `/opt/pangolin/config/db/db.sqlite` becomes `opt_pangolin_config_db_db.sqlite`. The live database is excluded from the archive, so step 3's copy of the app folder leaves it as it is. Check the copy first (`sqlite3 <copy> 'PRAGMA integrity_check'` prints `ok`). With the app stopped, copy it back to its original path and delete the old database's `-wal` and `-shm` files next to it (Pangolin runs in WAL: a leftover WAL would be replayed onto the restored copy). The copy comes out owned by `root:root` and in `journal_mode=delete` (`VACUUM INTO`): give it back the old file's owner (`stat -c %u:%g` before, `chown` after), and if the old one ran in WAL (`sqlite3 <old> 'PRAGMA journal_mode'` before replacing it), switch the copy back before starting the app: `sqlite3 <copy> 'PRAGMA journal_mode=WAL'`. The backup hook picks `VACUUM INTO` or `.backup` from the live mode at each run, and `.backup` never finishes on a database written all the time ([ansible/roles/borgmatic/README.md](../ansible/roles/borgmatic/README.md)).

Pangolin itself is a root systemd service, `pangolin`, so it is stopped and started with `systemctl stop pangolin` and `systemctl start pangolin` as root.
