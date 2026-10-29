# Role `nas_storage`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

## App data on the NAS

Apps can keep their data on the Ugreen NAS (NFSv3 export mounted on the
docker VM) while running on the VM; borg still backs everything up. Full
rationale and NAS-side setup: `nas-storage-docker/homelab-storage-architecture.md`.
No app uses it today: the pilot `nginx_demo` (nginx + an unused Postgres on
the export, removed on 2026-10-29) was its only consumer. Its last version
is in git history (`git show c945b564:ansible/roles/nginx_demo/tasks/main.yml`,
same for `defaults/`, `meta/`, `templates/compose.yaml` and
`ansible/molecule/nginx_demo/`); the snippets at the end are taken from it.
Nothing applies the role any more: the fstab entry, the slice and
`nas-storage-wait` it installed on the docker VM stay there, unused, until
an app depends on it again. The rules:

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
  next to the cluster on the NAS (`<service>_db_password_path`), not derived
  from `backup_passphrase`.
- Decommissioning: pass `<service>_data_path` in
  `decommission_app_extra_paths`, or the data stays orphaned on the NAS.
- Molecule: a container cannot mount the NFS export. Scenarios set
  `nas_storage_manage_mount: false` + `nas_storage_fstype: tmpfs` and reuse
  `ansible/molecule/nas_storage/prepare.yml`, which mounts a tmpfs (closed to
  "others") in its place: everything but the fstab/automount path is covered.
- No iSCSI: considered and rejected (see the doc).

## Reference snippets

From the removed `nginx_demo` pilot, `<service>` standing for the app. Its
Molecule scenario took `prepare: ../nas_storage/prepare.yml` in
`molecule.yml` and set `nas_storage_manage_mount: false` and
`nas_storage_fstype: tmpfs` in its converge `vars:`.

`meta/main.yml` (a dependency, not a `docker.yml` entry: `--tags <service>`
pulls it in too, and it runs once per play):

```yaml
dependencies:
  - role: nas_storage
```

`defaults/main.yml`:

```yaml
<service>_base_path: "{{ docker_base_path }}/<service>"        # compose.yaml, .env
<service>_data_path: "{{ nas_storage_mount_path }}/<service>"  # what exists once
<service>_db_password_path: "{{ <service>_data_path }}/db_password"
<service>_db_password: "{{ (<service>_db_password_file.content | default('')) | b64decode | trim }}"
# After dc@'s Docker wait (120 s at most) and pull, under its 300 s TimeoutStartSec.
<service>_nas_wait_timeout: 150
```

`tasks/main.yml`: the data dirs (each owned by the uid/gid that uses it in
the container, nothing for "others"; UGOS makes everything `0777` unless
chmod'ed, hence an explicit `mode:` everywhere) and the password drawn once:

```yaml
- name: Ensure the data folders exist on the NAS
  become: true  # NFS rule "No mapping": root creates and chowns as on a local disk
  loop:
    - { path: "{{ <service>_data_path }}", owner: "{{ ansible_facts['user_id'] }}", group: "{{ ansible_facts['user_gid'] }}", mode: "0750" }
    - { path: "{{ <service>_data_path }}/html", owner: "{{ ansible_facts['user_id'] }}", group: "101", mode: "0750" }  # files, read by nginx alpine (gid 101)
    - { path: "{{ <service>_data_path }}/postgresql", owner: "70", group: "70", mode: "0700" }  # postgres alpine
  loop_control:
    label: "{{ item.path }}"
  register: <service>_data_dirs
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    owner: "{{ item.owner }}"
    group: "{{ item.group }}"
    mode: "{{ item.mode }}"

# Postgres reads POSTGRES_PASSWORD at initdb only. Tagged backup: the
# borgmatic config needs it. Skipped on a first --check (no folder yet).
- name: Draw the database password once, next to its cluster
  become: true
  tags: backup
  no_log: true
  diff: false
  when: not (ansible_check_mode and (<service>_data_dirs | default({})) is changed)
  ansible.builtin.copy:
    dest: "{{ <service>_db_password_path }}"
    content: "{{ lookup('ansible.builtin.password', '/dev/null', length=48, chars=['ascii_letters', 'digits']) }}"
    force: false
    owner: root
    group: root
    mode: "0600"

- name: Read the database password
  become: true
  tags: backup
  no_log: true
  when: not (ansible_check_mode and (<service>_data_dirs | default({})) is changed)
  ansible.builtin.slurp:
    src: "{{ <service>_db_password_path }}"
  register: <service>_db_password_file
```

The NAS wait, a drop-in of this `dc@` instance only:

```yaml
- name: Ensure the dc@<service> drop-in directory exists
  ansible.builtin.file:
    path: "{{ ansible_facts['env']['HOME'] }}/.config/systemd/user/dc@<service>.service.d"
    state: directory
    mode: "0700"

- name: Wait for the NAS before starting dc@<service>
  diff: false
  ansible.builtin.copy:
    dest: "{{ ansible_facts['env']['HOME'] }}/.config/systemd/user/dc@<service>.service.d/nas-storage.conf"
    mode: "0600"
    content: |
      [Service]
      ExecStartPre={{ nas_storage_wait_command }} {{ <service>_nas_wait_timeout }}
```

The `vars:` of the `include_role: name=borgmatic tasks_from=app.yml` (the
data directory is dumped, never copied):

```yaml
    borgmatic_app_source_directories:
      - "{{ <service>_data_path }}/html"  # file folders on the NAS
      - "{{ <service>_base_path }}/compose.yaml"
      - "{{ <service>_base_path }}/.env"
    borgmatic_app_postgresql_databases:
      - container: <service>-db
        name: "{{ <service>_db_name }}"
        username: "{{ <service>_db_user }}"
        password: "{{ <service>_db_password }}"
    borgmatic_app_before_commands:
      - "{{ nas_storage_wait_command }} 30"  # a dead NAS fails this config only
    borgmatic_app_extra_options:
      source_directories_must_exist: true  # an unmounted export fails, no empty archive
```

`templates/compose.yaml`, on every container whose data is on the NAS:

```yaml
  <service>-db:
    cgroup_parent: {{ nas_storage_slice }}  # stopped before the NAS is unmounted
    stop_grace_period: 60s                  # its last checkpoint goes over NFS
    environment:
      POSTGRES_PASSWORD: ${<SERVICE>_DB_PASSWORD:?Variable is required and must be set}
    volumes:
      - {{ <service>_data_path }}/postgresql:/var/lib/postgresql
```
