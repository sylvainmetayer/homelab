# Role `nas_storage`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

## App data on the NAS

Apps can keep their data on the Ugreen NAS (NFSv3 export mounted on the
docker VM) while running on the VM; borg still backs everything up. Full
rationale and NAS-side setup: `nas-storage-docker/homelab-storage-architecture.md`.
Reference role: `ansible/roles/nginx_demo`. The rules:

- Declare `dependencies: [{role: nas_storage}]` in the app's `meta/main.yml`
  (not in `docker.yml`): it mounts `/mnt/nas/apps` (`hard`,
  `x-systemd.automount`) and runs once per play whatever the number of apps.
  `resolve_docker_tags.py` follows meta dependencies, so a `nas_storage`
  change redeploys its dependents.
- Data under `<service>_data_path: "{{ nas_storage_mount_path }}/<service>"`,
  created with `become: true` (the NFS rule is "No mapping" for the VM's IP),
  bind-mounted by absolute path. Never a Docker `driver_opts: nfs` volume:
  borg can't read it. UGOS creates every file and directory `0777` whatever
  the umask, but honours an explicit chmod: give each NAS path an explicit
  `mode:`.
- UGOS Pro 1.20 serves NFSv3 only (`nas_storage_nfs_version: "3"`): NFSv4.1
  can be enabled but UGOS declares no v4 pseudo-root. The VM's export is
  published by `nas.yml` (`host_vars/nas`), always `sync`; a rule added in the
  UI instead has "Async" ticked by default.
- Postgres/MariaDB data dirs may live there; **SQLite (and any mmap/lock-based
  embedded DB) never does** — it stays on the local disk.
- Every NAS-backed container gets `cgroup_parent: {{ nas_storage_slice }}`:
  that slice is ordered after the mount, so at VM shutdown the containers stop
  before the NAS is unmounted and the network goes down (a `hard` mount would
  otherwise hang Postgres' last checkpoint).
- A `dc@<service>.service.d/nas-storage.conf` user drop-in with
  `ExecStartPre={{ nas_storage_wait_command }} <timeout>`: at boot the VM is
  up before the NAS, and without the wait every `docker compose up` fails on
  the automount (30 s) with a Docker bind-mount error, retried by dc@ forever.
  dc@'s `TimeoutStartSec` (300 s) covers all its `ExecStartPre`: its Docker
  wait (up to 120 s) and the pull come first, so keep the NAS wait at 150 s
  or less.
- Borgmatic (`borgmatic` role, `tasks_from: app.yml`): NAS file dirs in
  `borgmatic_app_source_directories`, the DB data dir **not** (dumped through
  `borgmatic_app_postgresql_databases`),
  `borgmatic_app_extra_options: {source_directories_must_exist: true}`, and
  `borgmatic_app_before_commands: ["{{ nas_storage_wait_command }} 30"]`
  (runs before borg reads the NAS): without it a dead NAS blocks the single
  `borgmatic.service`, hence every app's backup.
- DB passwords that Postgres only reads at initdb are drawn once and stored
  next to the cluster on the NAS (`nginx_demo_db_password_path`), not derived
  from `backup_passphrase`.
- Decommissioning: pass `<service>_data_path` in
  `decommission_app_extra_paths`, or the data stays orphaned on the NAS.
- Molecule: a container cannot mount the NFS export. Scenarios set
  `nas_storage_manage_mount: false` + `nas_storage_fstype: tmpfs` and reuse
  `ansible/molecule/nas_storage/prepare.yml`, which mounts a tmpfs (closed to
  "others") in its place: everything but the fstab/automount path is covered.
- No iSCSI: considered and rejected (see the doc).
