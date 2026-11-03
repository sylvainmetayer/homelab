# Role `decommission_app`

Stops an app and deletes it from its host: containers, volumes, data, borgmatic config, optionally the remote Borg repository. It is step 1 of the `remove-app` skill (`.claude/skills/remove-app/SKILL.md`, which holds the command and everything left to clean in the repo: role, playbook, secrets, Tofu).

In `docker.yml`, `pi.yml`, `flip.yml` and `nas.yml`, `tags: [decommission, never]`: it runs only with an explicit `--tags decommission`, never under `--tags all` nor from a merge (`resolve_docker_tags.py` prints a notice and deploys nothing). No entry in `pangolin.yaml` or `lxc.yml`.

## What it does, in order

1. Refuses without `decommission_app_confirm`, `decommission_app_service` and `decommission_app_base_path`, refuses a base path other than `<docker_base_path>/<service>` (`/opt/apps`, `/volume1/docker` on the NAS; `dc@<service>` always runs there, `dc@.service`'s `WorkingDirectory`), and any `decommission_app_extra_paths` entry other than `<nas_storage_mount_path>/<service>`. Nothing has been stopped yet.
2. With `decommission_app_destroy_remote_backup` (default `false`): `borgmatic --config <service>.yaml repo-delete --force`. **Irreversible.** A failure stops the run there, with the app still running and nothing removed: fix the cause and run again. A repository already absent is not a failure (`ok`, not `changed`).
3. Stops and disables `dc@<service>`. A failure stops the run there, with the unit already disabled (`systemd` disables first): the app keeps running but would not come back after a reboot. Only a unit that cannot be found is tolerated.
4. `docker compose down --volumes --remove-orphans` in the base path. A failure stops the run there (data and borgmatic config stay); only a missing folder or compose file is tolerated.
5. Removes `<service>.yaml` and `uptime-kuma/<service>.curl` from `borgmatic_config_dir` (switch: `decommission_app_remove_borgmatic_config`).
6. Removes the base path and the extra paths as root (switch: `decommission_app_remove_data`).
7. Removes the `dc@<service>.service.d` drop-ins, then reloads systemd.

The shared `dc@.service` template stays. On the NAS (`docker_service_scope: system`, derived in `vars/main.yml`), the unit is a system one and root runs compose; `decommission_app_borgmatic_bin` follows `borgmatic_bin`, the container wrapper there.

## Non-obvious or dangerous

- **A failed stop comes after `repo-delete`**: with `decommission_app_destroy_remote_backup`, the repository is already gone when step 3 or 4 fails, while the data and the config are still there. Until then the nightly backup of this app fails on the config left behind. Fix the cause and run again: the absent repository is tolerated.
- **`ok` on the compose task means it found no compose file** (`no configuration file provided`, exit code 1 or 14 depending on compose's version), and the folder is deleted all the same. The project's containers and named volumes, if any, stay: `docker compose -p <service> down --volumes` removes them.
- **`repo-delete` needs the borgmatic config**: a first run without `decommission_app_destroy_remote_backup` removes it, and a later run with it fails (« No valid configuration files found »), as does a run again after a successful delete: drop the switch then. Deleting a repository left behind needs its config back (`--tags backup` while the role is still there). Decide before the first run, or keep the config with the switch.
- **The config is read and removed under the service's name**: `kdrive_sync`'s is `kdrive.yaml` (`borgmatic_app_name: kdrive`), so this role neither removes it nor deletes its repository (with the switch, the run stops at step 2). Remove `kdrive.yaml` and `uptime-kuma/kdrive.curl` by hand if its opt-in backup is on.
- **« Already absent » is read off borgmatic's output** (`Repository … does not exist.`, borg exit code 13; borgmatic itself always exits 1). It also holds for a config pointing at the wrong place: `ok` on this task means nothing was deleted.
- **An app with data on the NAS** must pass its `<service>_data_path` in `decommission_app_extra_paths`, or its files and database cluster stay orphaned there. Nothing else outside the base path is deleted: `ansible/roles/mediamanager/README.md` has such a case.
- Docker images are not removed (no `--rmi`); the weekly prune of `docker_service` (user-scope hosts, not the NAS) takes the unused ones.
- A move between hosts must not destroy the backup (`flip.yml`, top of the file: `decommission_app` on the old host, without `destroy_remote_backup`).

## Testing

`mise run molecule decommission_app`: `prepare.yml` deploys `rss` and `wiki`, the converge decommissions `rss` under user scope, the verify checks that the unit is stopped and disabled, that the data and borgmatic files are gone, and that `wiki` and the shared paths are intact. `side_effect.yml` then checks, on fixtures, the refused paths (nothing stopped or deleted), the switches as strings and `decommission_app_extra_paths`, and `repo-delete` with the real borgmatic and borg against throwaway local repositories: failed (config kept), absent, deleted. It also checks a compose file that is invalid and a unit that refuses to stop (data and config kept), and tolerates a missing compose file and a missing unit, the latter under system scope. **Not covered**: the removal of the drop-ins, the NAS's system unit and borgmatic container wrapper, a repository over SSH.

## Pointers

Procedure: `remove-app` skill, summary in `docs/conventions/app-lifecycle.md`. Pausing an app instead (keeps everything): `docs/runbooks/app-en-pause.md`. Backups: `ansible/roles/borgmatic/README.md`.
