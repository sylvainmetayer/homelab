# Container hardening

Agent-facing notes, in English like the other conventions; `AGENTS.md` links here. Covers `security_opt` and capabilities only, `read_only` and the network stay each role's call.

## Default

Every service of a compose template starts from:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
```

- **`no-new-privileges` always**, unless the service is listed below. It only stops a gain of privileges through a setuid or setgid binary or file capabilities: an entrypoint started as root that drops to another user (`gosu`, `su-exec`, `setpriv`, s6) still works. What breaks is a process **already unprivileged** calling `sudo`, `su`, a setuid or setgid helper, or a binary that relies on its file capabilities.
- **`cap_drop: [ALL]` when the image runs unprivileged from its first instruction** (`USER` or `user:`): it has no effective capability to lose. An image started as root gets it only with a tested `cap_add`, possibly empty (the `beszel` hub), written in the compose next to a comment saying which entrypoint call needs each one (`homepage`). A root process with no `CAP_DAC_OVERRIDE` can no longer write a bind mount owned by the deploy user: give the folder to the uid that writes in it (`beszel`, `trek`), or keep `DAC_OVERRIDE` when the entrypoint must cross it (a `chown -R` through a `0700` mount, `dawarich-app`; through www-data's folders, `rss`).
- `borgmatic` (NAS, `ansible/roles/borgmatic/templates/compose.yaml`): `cap_drop: [ALL]` + `cap_add: [DAC_OVERRIDE]` + `no-new-privileges`, tried on the NAS itself on 2026-11-09 (real backup of Jellyfin, `create --stats`, 4198 files read). Root in the container reads the `0700` folders of other accounts (Jellyfin's `config` is `1000:10`, MediaManager's databases); without `DAC_OVERRIDE`, `Permission denied` on them (checked with the image run under `--cap-drop ALL`). Nothing else for a backup, which only reads; an `extract` (restore, `docs/runbooks/disque-nas-mort.md`) does chown, and without `CHOWN` borg leaves everything `root:root` without failing: add `--cap-add CHOWN --cap-add FOWNER` to that one run (checked on 2026-11-10: Jellyfin's `config/config` extracted as `0:0` without, `1000:10` with). Without `CHOWN` and `FOWNER`, borg falls back to a plain `open` (no `O_NOATIME`) on files of other accounts, and the `sqlite3` of the `before` hooks no longer hands a `-wal`/`-shm` it creates back to the database's owner (not tried with the application stopped).
- A `cap_add` stays inside Docker's default set. In particular never `DAC_READ_SEARCH`, although it would do for the crossing above: it is not in that set, and Docker's default seccomp profile opens `open_by_handle_at` to it, the Shocker path to the host's files through a bind mount (measured on a rootful runner: `EPERM` by default, with no capability and with `DAC_OVERRIDE`, the call reaches the kernel with `DAC_READ_SEARCH`). Rootless tests cannot show it.
- An image that changes user may fail silently: without `SETGID`, Apache logs nothing fatal and keeps its workers as **root** (`rss`, tested without it). Its master also needs `KILL` to signal workers of another uid, or a stop waits for the SIGKILL. So read `Uid` and `CapEff` of every process in `/proc/<pid>/status`, a healthy state proves nothing.
- A `docker exec` as root has the container's capabilities: where `DAC_OVERRIDE` is gone, use `-u` with the uid that owns the files.
- `sudo` from root still works under the option, from `abc` it does not: Nextcloud's `occ` wrapper is `sudo -u abc`, so `docker exec nextcloud occ …` works, `docker exec -u abc nextcloud occ …` fails. A setuid `ping` falls back to an ICMP socket through Docker's default `ping_group_range` (speedtest-tracker); not under `network_mode: host`.
- A new app takes a line off only when a row below covers the service, or with a comment giving the reason. For `no-new-privileges` a comment is not enough: the service goes in the table and in `EXCEPTIONS` (below).

## Exceptions

| Service | Missing | Reason |
|---|---|---|
| Databases (postgres, mariadb, redis, valkey, meilisearch) | `cap_drop` | Most start as root and hand over their data directory, meilisearch stays root and writes in it; a wrong capability shows up at a restart, on data. Not worth the risk for a service on an internal network. |
| s6 images (linuxserver and alike: `grocy`, `speedtest_tracker`, `wiki`, `nextcloud`, `betisier`, `karakeep` web…) | `cap_drop` | `/init` chowns `/config`, adjusts `abc` to PUID/PGID and runs services as `abc`; the set of capabilities depends on the image's init scripts and can change with any update. |
| `wishlist` | `cap_drop` | See its compose: root writing in the deploy user's folders. |
| `gluetun` (`mediamanager`) | `cap_drop` | Starts as root with `NET_ADMIN` for the tunnel and its firewall; the other capabilities it needs were not analysed. |
| Immich, Pangolin, Newt (not its socket proxy), `flip_planning`, Monica | `cap_drop` (Immich, Newt), both (the others) | Out of scope for now: family service, the access path to everything else, production, a paused app, an app frozen until December 2026. Immich (server, machine learning, Postgres, Valkey, Swipe, Selfie Timelapse) and Newt have `no-new-privileges` since 2026-11-05. Inspected with `find / -xdev -perm /6000`: Newt (Alpine, `entrypoint.sh` then `exec newt`, no `USER`), Valkey, Swipe and Selfie Timelapse: root, no change of user, only the distribution's standard setuid binaries. Read off upstream, images not run: immich-server and machine-learning (no `USER`, `tini` then a script that `exec`s node or python), Postgres (Immich's entrypoint `exec`s the official `docker-entrypoint.sh`, not read, which by its usual pattern drops to `postgres` with `gosu`, allowed by the option). After the deploy, check `RestartCount` and the logs. `cap_drop` stays undone, no image analysis. Exceptions: Swipe has `cap_drop: ALL` plus `CHOWN`, `DAC_OVERRIDE`, `SETGID`, `SETUID` since 2026-11-10 (tried locally, `immich` role README); the machine learning of the NAS (role `immich_ml`, OpenVINO image) has `cap_drop: ALL` since 2026-11-09, not read off the image either; the Pi's fallback hides a crash loop, so check its logs after the first deploy (role README). The other four: not an analysis of the image, to be done before lifting them. |

`check_container_hardening.py` (Lint) enforces the `no-new-privileges` column: its `EXCEPTIONS` list and this table move together. Nothing checks `cap_drop`.

## Docker Bench : écarts assumés

Triage of the 2026-11-05 report, redone on 2026-11-10 (docker-bench-security from GitHub, run read-only as root on docker, pi, pangolin and flip; the `docker/docker-bench-security` image fails against a recent daemon, « Error connecting to docker daemon »: use the script). Classes: (a) upstream image or the benchmark does not fit, (b) accepted, reason written in the repo, (c) small and safe to fix, (d) Sylvain to decide. **No (c) was left**: what remained is either tied to an image or touches the daemon. A WARN below is not to be fixed again without a new reason.

| Check | Where | Class | Why |
|---|---|---|---|
| 1.1.1 separate partition for `/var/lib/docker` | all | b | Single-disk VMs; the volumes are the data. |
| 1.1.8, 1.1.10, 1.1.11 auditd on `containerd.sock`, `/etc/default/docker`, `daemon.json` | all | b | `security` role: sockets left out (one event per client connection), `/etc/default/docker` absent on Debian, `/etc/docker` already watched (`ansible/roles/security/README.md`). |
| 2.2 `icc` on the default bridge | all | b | Compose services run on their own networks, not the default bridge (not re-checked container by container); DBs sit on internal networks. |
| 2.9 userns-remap | all | d | Daemon change, restarts every container, breaks bind mounts owned by the deploy user and `network_mode: host` agents. |
| 2.12 authorization plugin | all | a | No plugin worth running for one operator; the socket is reached through `wollomatic/socket-proxy` (Newt, Beszel, log agent). |
| 2.13 remote logging | all | b | Logs go to VictoriaLogs through the log agent reading the socket proxy, not through a logging driver. |
| 2.14 daemon-wide `no-new-privileges` | all | d | Daemon change; per service it is already enforced by `check_container_hardening.py`. A daemon default would hit the exceptions below. |
| 2.15 live-restore | all | b | Decided 2026-11-05, see below. |
| 2.16 userland proxy | all | d | Daemon change (`userland-proxy: false`), a restart of Docker; published ports of the Pi (Immich, Blocky) and Pangolin (80, 443) would then rely on hairpin NAT. |
| 4.1 containers running as root | docker, pi, pangolin, flip | b | s6 images, databases, `newt`, agents on `network_mode: host`: see the table above; every one has `cap_drop` or a row there. |
| 4.5 content trust | all | a | Images are pinned by digest instead (Renovate), a stronger guarantee for registries without Notary. |
| 4.6 image without `HEALTHCHECK`, 5.27 no health check at runtime | all | a | Most services declare `healthcheck:` in compose; what is left (socket proxies, `victoria-logs`, `newt`, log agent, `gerbil`, `traefik`) are images with no shell nor `wget`, or the monitored path is the public route (Uptime Kuma). |
| 5.2 AppArmor profile | pi | a | Raspberry Pi OS kernel without AppArmor; the docker VM, pangolin and flip show no WARN. |
| 5.3 SELinux | docker (Monica), pangolin, flip | a | Debian, no SELinux. |
| 5.4 `CAP_SYS_RAWIO` | pi (beszel-agent) | b | S.M.A.R.T. reading, see the `beszel_agent` defaults. |
| 5.4 `CAP_NET_ADMIN` | pangolin (gerbil) | a | WireGuard interface, upstream requirement. |
| 5.8, 5.9, 5.14 privileged ports, open ports, wildcard bind | pangolin (gerbil 80, 443, 51820, 21820), pi (blocky 53, immich 2283) | b | The public entry points and the LAN services by design; `ufw` filters them, `5.9` also lists ports the image `EXPOSE`s (`vmauth` 9428, `beszel` 8090). |
| 5.10 host network | `beszel-agent`, `log-agent` | b | They read the host's disks, network and journal. |
| 5.12 CPU restriction | all | b | Doctrine: no `cpus:` except batch workers (`resource-limits.md`). |
| 5.13 root filesystem read-write | most services | d | Per-app work, each needs a test of the writes it does (`/tmp`, caches, s6 and `/run`); services that support it already have `read_only: true`. One PR per app when Sylvain picks one. Picked on 2026-11-10: papra, karakeep's `chrome`, yamtrack; done: ntfy (`/tmp` only, `docker diff` showed no other write), homebox (`/tmp` for the upload parts Go spills to disk; its empty `~/.cache/goimports` is not needed), healthlog's `app` (`/tmp` for tsx; the Prisma CLI runs the migrations without its caches under `~`). |
| 5.26 no-new-privileges | docker (Monica), pangolin, flip (`flip_planning` stack) | b for Monica and Pangolin, d for flip | Rows of the exceptions table. The flip stack (production, mailpit, pgadmin, assets, DB) has no row: lifting it is an analysis of the images, then a deploy on production. |
| 5.29 PIDs limit | all | b | `resource-limits.md`, decision of 2026-11-05: none without a measure. |
| 5.32 Docker socket mounted | the three `*-socket-proxy` | b | The point of those containers: read-only filtered API for Newt, Beszel and the log agent; no other container mounts it. |

`live-restore` stays off (Docker Bench 2.13). Units `dc@` would not benefit: `compose up` exits when the daemon stops, then `ExecStop` stops the containers. Turning it on gains nothing there, and enabling it by a daemon restart would restart every container of the host once (a `SIGHUP` reload would not). Only the Pangolin stack, outside `dc@`, would gain, and restarting it cuts every public route. Decided on 05/11/2026.

## Testing a change

Molecule pulls no image: a crash only shows in production. So, before a merge, for any image with a risk (s6, an entrypoint changing user, setuid binaries):

1. `docker inspect` of the running container (`Config.User`, `Config.Entrypoint`, `HostConfig.SecurityOpt`, `HostConfig.CapDrop`), and the image's upstream doc.
2. List the setuid and setgid binaries and who may call them: `find / -xdev \( -perm -4000 -o -perm -2000 \) -type f`, and the file capabilities where the image has the tool: `getcap -r / 2>/dev/null`. Root calling one is fine; `abc` or `www-data` calling `sudo` is not.
3. Start the pinned image locally with the options, rootful and with a bind mount owned by a non-root user (`sudo podman run --security-opt no-new-privileges --cap-drop ALL --cap-add … -v …`): rootless podman maps that owner to the container's root, which hides a lost `CAP_DAC_OVERRIDE`. With no root at hand, `podman run --userns=keep-id --user 0:0` keeps that owner distinct from the container's root; add `--sysctl net.ipv4.ip_unprivileged_port_start=0`, which Docker sets by default on a bridge network and podman does not. A pull request can also run the rootful test on a GitHub runner in a temporary workflow (no secret, fictitious data), removed before the merge. Check `grep NoNewPrivs /proc/1/status`, and exercise what runs later: a cron, a queue worker, a helper such as `occ`. Then remove each capability in turn to prove the list is minimal.

After the deploy (a green deploy says nothing, the container may be looping): state `healthy` or `running`, `RestartCount` at 0, no permission error in the recent logs, `SecurityOpt` as expected, an HTTP answer from the app.

Break after a merge: revert in a PR, verify, add the image to the table above with what failed. When an image update brought the break, also drop the image from Renovate's automerge allowlist (`homepage` is on it, and its `cap_add` depends on its entrypoint), or the next Monday merges the same digest again.
