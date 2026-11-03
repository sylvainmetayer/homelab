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
- **`cap_drop: [ALL]` when the image runs unprivileged from its first instruction** (`USER` or `user:`): it has no effective capability to lose. An image started as root gets it only with a tested `cap_add`, possibly empty (the `beszel` hub), written in the compose next to a comment saying which entrypoint call needs each one (`homepage`). A root process with no `CAP_DAC_OVERRIDE` can no longer write a bind mount owned by the deploy user: give the folder to the uid that writes in it (`beszel`, `trek`).
- `sudo` from root still works under the option, from `abc` it does not: Nextcloud's `occ` wrapper is `sudo -u abc`, so `docker exec nextcloud occ …` works, `docker exec -u abc nextcloud occ …` fails. A setuid `ping` falls back to an ICMP socket through Docker's default `ping_group_range` (speedtest-tracker); not under `network_mode: host`.
- A new app takes a line off only when a row below covers the service, or with a comment giving the reason. For `no-new-privileges` a comment is not enough: the service goes in the table and in `EXCEPTIONS` (below).

## Exceptions

| Service | Missing | Reason |
|---|---|---|
| Databases (postgres, mariadb, redis, valkey, meilisearch) | `cap_drop` | Most start as root and hand over their data directory, meilisearch stays root and writes in it; a wrong capability shows up at a restart, on data. Not worth the risk for a service on an internal network. |
| s6 images (linuxserver and alike: `grocy`, `speedtest_tracker`, `wiki`, `nextcloud`, `betisier`, `karakeep` web…) | `cap_drop` | `/init` chowns `/config`, adjusts `abc` to PUID/PGID and runs services as `abc`; the set of capabilities depends on the image's init scripts and can change with any update. |
| `dawarich-app` | `cap_drop` | Its entrypoint runs `chown -R` on `tmp` and `db` (root's in the image) at each recreation, through `tmp/imports/watched`, a `0700` mount of the deploy user: it needs `CAP_DAC_READ_SEARCH` on top of `CHOWN`, `SETUID`, `SETGID`, and only a rootful test can settle the list. |
| `rss` | `cap_drop` | Apache's master and cron stay root, the entrypoint chowns the data, cron calls `su www-data`. Not analysed further. |
| `stirling_pdf`, `wishlist` | `cap_drop` | See their compose: `usermod`, `chown` and `setpriv` for one, root writing in the deploy user's folders for the other. |
| `gluetun` (`mediamanager`) | `cap_drop` | Starts as root with `NET_ADMIN` for the tunnel and its firewall; the other capabilities it needs were not analysed. |
| `borgmatic` (NAS) | both | `nas.yml` runs by hand; not tried yet. |
| Immich, Pangolin, Newt (not its socket proxy), `flip_planning`, Paperless (paused), Monica | both | Out of scope for now: family service, the access path to everything else, production, a paused app, an app frozen until December 2026. Not an analysis of the image: to be done before lifting them. |

`check_container_hardening.py` (Lint) enforces the `no-new-privileges` column: its `EXCEPTIONS` list and this table move together. Nothing checks `cap_drop`.

## Testing a change

Molecule pulls no image: a crash only shows in production. So, before a merge, for any image with a risk (s6, an entrypoint changing user, setuid binaries):

1. `docker inspect` of the running container (`Config.User`, `Config.Entrypoint`, `HostConfig.SecurityOpt`, `HostConfig.CapDrop`), and the image's upstream doc.
2. List the setuid and setgid binaries and who may call them: `find / -xdev \( -perm -4000 -o -perm -2000 \) -type f`, and the file capabilities where the image has the tool: `getcap -r / 2>/dev/null`. Root calling one is fine; `abc` or `www-data` calling `sudo` is not.
3. Start the pinned image locally with the options, rootful and with a bind mount owned by a non-root user (`sudo podman run --security-opt no-new-privileges --cap-drop ALL --cap-add … -v …`): rootless podman maps that owner to the container's root, which hides a lost `CAP_DAC_OVERRIDE`. Check `grep NoNewPrivs /proc/1/status`, and exercise what runs later: a cron, a queue worker, a helper such as `occ`.

After the deploy (a green deploy says nothing, the container may be looping): state `healthy` or `running`, `RestartCount` at 0, no permission error in the recent logs, `SecurityOpt` as expected, an HTTP answer from the app.

Break after a merge: revert in a PR, verify, add the image to the table above with what failed. When an image update brought the break, also drop the image from Renovate's automerge allowlist (`homepage` is on it, and its `cap_add` depends on its entrypoint), or the next Monday merges the same digest again.
