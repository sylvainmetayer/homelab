# Container hardening

Agent-facing notes, in English like the other conventions; `AGENTS.md` links here. Covers `security_opt` and capabilities only, `read_only` and the network stay each role's call.

## Default

Every service of a compose template:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
```

- **`no-new-privileges` always**, unless the service is listed below. It only stops a gain of privileges through a setuid binary or file capabilities: an entrypoint started as root that drops to another user (`gosu`, `su-exec`, `setpriv`, s6) still works. What breaks is a process **already unprivileged** calling `sudo`, `su` or a setuid helper.
- **`cap_drop: [ALL]` when the image runs unprivileged from its first instruction** (`USER` or `user:`): it has no effective capability to lose. An image started as root gets it only with a tested `cap_add`, written in the compose next to a comment saying which entrypoint call needs each one (`trek`, `homepage`). A root process with no `CAP_DAC_OVERRIDE` can no longer write a bind mount owned by the deploy user.
- A new app starts from both lines, and takes one off only with a comment giving the reason.

## Exceptions

| Service | Missing | Reason |
|---|---|---|
| Databases (postgres, mariadb, redis, valkey, meilisearch) | `cap_drop` | They start as root and hand over their data directory; a wrong capability shows up at a restart, on data. Not worth the risk for a service on an internal network. |
| s6 images (linuxserver and alike: `grocy`, `speedtest_tracker`, `wiki`, `nextcloud`, `betisier`, `karakeep` web…) | `cap_drop` | `/init` chowns `/config`, adjusts `abc` to PUID/PGID and runs services as `abc`; the set of capabilities depends on the image's init scripts and can change with any update. |
| `stirling_pdf`, `wishlist` | `cap_drop` | See their compose: `usermod`, `chown` and `setpriv` for one, root writing in the deploy user's folders for the other. |
| Immich, Blocky (Pi), Pangolin, Newt, `flip_planning`, Paperless (paused), Monica | both | Out of scope for now: family service, DNS, the access path to everything else, production, a paused app, an app frozen until December 2026. Not an analysis of the image: to be done before lifting them. |

## Testing a change

Molecule pulls no image: a crash only shows in production. So, before a merge, for any image with a risk (s6, an entrypoint changing user, setuid binaries):

1. `docker inspect` of the running container (`Config.User`, `Config.Entrypoint`, `HostConfig.SecurityOpt`, `HostConfig.CapDrop`), and the image's upstream doc.
2. List the setuid binaries and who may call them: `find / -xdev -perm -4000 -type f`, then `grep NoNewPrivs /proc/1/status`. Root calling one is fine; `abc` or `www-data` calling `sudo` is not.
3. Start the pinned image locally with the option (`podman run --security-opt no-new-privileges …`), and exercise what runs later: a cron, a queue worker, a helper such as `occ`.

After the deploy (a green deploy says nothing, the container may be looping): state `healthy` or `running`, `RestartCount` at 0, no permission error in the recent logs, `SecurityOpt` as expected, an HTTP answer from the app.

Break after a merge: revert in a PR, verify, add the image to the table above with what failed.
