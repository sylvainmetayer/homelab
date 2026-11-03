# Role `decommission_app`

Stops an app and deletes it from its host: containers, volumes, data, borgmatic config, optionally the remote Borg repository. It is step 1 of the `remove-app` skill (`.claude/skills/remove-app/SKILL.md`, which holds the command and everything left to clean in the repo: role, playbook, secrets, Tofu).

In `docker.yml`, `pi.yml`, `flip.yml` and `nas.yml`, `tags: [decommission, never]`: it runs only with an explicit `--tags decommission`, never under `--tags all` nor from a merge (`resolve_docker_tags.py` prints a notice and deploys nothing). No entry in `pangolin.yaml` or `lxc.yml`.

## What it does, in order

1. Refuses without `decommission_app_confirm`, `decommission_app_service` and `decommission_app_base_path`, and refuses any `decommission_app_extra_paths` entry other than `<nas_storage_mount_path>/<service>`.
2. Stops and disables `dc@<service>`.
3. `docker compose down --volumes --remove-orphans` in the base path.
4. With `decommission_app_destroy_remote_backup` (default `false`): `borgmatic --config <service>.yaml repo-delete --force`. **Irreversible.**
5. Removes `<service>.yaml` and `uptime-kuma/<service>.curl` from `borgmatic_config_dir` (switch: `decommission_app_remove_borgmatic_config`).
6. Removes the base path and the extra paths as root (switch: `decommission_app_remove_data`).
7. Removes the `dc@<service>.service.d` drop-ins, then reloads systemd.

The shared `dc@.service` template stays. On the NAS (`docker_service_scope: system`, derived in `vars/main.yml`), the unit is a system one and root runs compose; `decommission_app_borgmatic_bin` follows `borgmatic_bin`, the container wrapper there.

## Non-obvious or dangerous

- **A green run proves nothing about steps 2 to 4**: the three tasks have `failed_when: false` (compose's comment gives one reason: on a second pass, the folder is gone). Read their status: compose and `repo-delete` report `changed` only on `rc == 0`, so `ok` means they failed. If compose failed, the data is still deleted, and containers may be left running.
- **A failed `repo-delete` still loses its config**: step 5 runs regardless, unless switched off. Likewise, a first run without `decommission_app_destroy_remote_backup` removes the config, and a later run with it silently fails for lack of that file: this role can then no longer delete the repository. Decide before the first run, or keep the config with the switch.
- **The two switches only take a real boolean**: `decommission_app_remove_borgmatic_config` and `decommission_app_remove_data` are read by a bare `when:`, so `-e decommission_app_remove_data=false` (a string) makes ansible-core 2.21 fail the task, once steps 2 to 4 have already run. Pass JSON: `-e '{"decommission_app_remove_data": false}'`. `decommission_app_confirm` and `decommission_app_destroy_remote_backup` go through `| bool` and accept both.
- **`decommission_app_base_path` is only checked for being non-empty**, then deleted as root. Only `decommission_app_extra_paths` has the strict check, because `/mnt/nas/apps` without `/<service>` would empty the NAS of every app. Read the `-e` twice.
- **An app with data on the NAS** must pass its `<service>_data_path` in `decommission_app_extra_paths`, or its files and database cluster stay orphaned there. Nothing else outside the base path is deleted: `ansible/roles/mediamanager/README.md` has such a case.
- Docker images are not removed (no `--rmi`); the weekly prune of `docker_service` (user-scope hosts, not the NAS) takes the unused ones.
- A move between hosts must not destroy the backup (`flip.yml`, top of the file: `decommission_app` on the old host, without `destroy_remote_backup`).

## Testing

`mise run molecule decommission_app`: `prepare.yml` deploys `rss` and `wiki`, the converge decommissions `rss` under user scope, the verify checks that the unit is stopped and disabled, that the data and borgmatic files are gone, and that `wiki` and the shared paths are intact. **Not covered**: `decommission_app_destroy_remote_backup`, `decommission_app_extra_paths`, the toggles, the removal of the drop-ins, the NAS's system scope.

## Pointers

Procedure: `remove-app` skill, summary in `docs/conventions/app-lifecycle.md`. Pausing an app instead (keeps everything): `docs/runbooks/app-en-pause.md`. Backups: `ansible/roles/borgmatic/README.md`.
