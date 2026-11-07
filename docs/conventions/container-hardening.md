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
| `borgmatic` (NAS) | both | `nas.yml` runs by hand; not tried yet. |
| Immich, Pangolin, Newt (not its socket proxy), `flip_planning`, Monica | `cap_drop` (Immich, Newt), both (the others) | Out of scope for now: family service, the access path to everything else, production, a paused app, an app frozen until December 2026. Immich (server, machine learning, Postgres, Valkey, Swipe, Selfie Timelapse) and Newt have `no-new-privileges` since 2026-11-05. Inspected with `find / -xdev -perm /6000`: Newt (Alpine, `entrypoint.sh` then `exec newt`, no `USER`), Valkey, Swipe and Selfie Timelapse: root, no change of user, only the distribution's standard setuid binaries. Read off upstream, images not run: immich-server and machine-learning (no `USER`, `tini` then a script that `exec`s node or python), Postgres (Immich's entrypoint `exec`s the official `docker-entrypoint.sh`, not read, which by its usual pattern drops to `postgres` with `gosu`, allowed by the option). After the deploy, check `RestartCount` and the logs. `cap_drop` stays undone, no image analysis. The other four: not an analysis of the image, to be done before lifting them. |

`check_container_hardening.py` (Lint) enforces the `no-new-privileges` column: its `EXCEPTIONS` list and this table move together. Nothing checks `cap_drop`.

## Docker Bench findings left as they are

`live-restore` stays off (Docker Bench 2.13). Units `dc@` would not benefit: `compose up` exits when the daemon stops, then `ExecStop` stops the containers. Turning it on gains nothing there, and enabling it by a daemon restart would restart every container of the host once (a `SIGHUP` reload would not). Only the Pangolin stack, outside `dc@`, would gain, and restarting it cuts every public route. Decided on 05/11/2026.

## Testing a change

Molecule pulls no image: a crash only shows in production. So, before a merge, for any image with a risk (s6, an entrypoint changing user, setuid binaries):

1. `docker inspect` of the running container (`Config.User`, `Config.Entrypoint`, `HostConfig.SecurityOpt`, `HostConfig.CapDrop`), and the image's upstream doc.
2. List the setuid and setgid binaries and who may call them: `find / -xdev \( -perm -4000 -o -perm -2000 \) -type f`, and the file capabilities where the image has the tool: `getcap -r / 2>/dev/null`. Root calling one is fine; `abc` or `www-data` calling `sudo` is not.
3. Start the pinned image locally with the options, rootful and with a bind mount owned by a non-root user (`sudo podman run --security-opt no-new-privileges --cap-drop ALL --cap-add … -v …`): rootless podman maps that owner to the container's root, which hides a lost `CAP_DAC_OVERRIDE`. With no root at hand, `podman run --userns=keep-id --user 0:0` keeps that owner distinct from the container's root; add `--sysctl net.ipv4.ip_unprivileged_port_start=0`, which Docker sets by default on a bridge network and podman does not. A pull request can also run the rootful test on a GitHub runner in a temporary workflow (no secret, fictitious data), removed before the merge. Check `grep NoNewPrivs /proc/1/status`, and exercise what runs later: a cron, a queue worker, a helper such as `occ`. Then remove each capability in turn to prove the list is minimal.

After the deploy (a green deploy says nothing, the container may be looping): state `healthy` or `running`, `RestartCount` at 0, no permission error in the recent logs, `SecurityOpt` as expected, an HTTP answer from the app.

Break after a merge: revert in a PR, verify, add the image to the table above with what failed. When an image update brought the break, also drop the image from Renovate's automerge allowlist (`homepage` is on it, and its `cap_add` depends on its entrypoint), or the next Monday merges the same digest again.
