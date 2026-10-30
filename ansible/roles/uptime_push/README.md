# Role `uptime_push`

Installs `uptime-push` (`files/uptime-push`, POSIX sh), the one place that sets the curl options of every Uptime Kuma push made from a shell script or a systemd unit. Installed at `uptime_push_bin` (`/usr/local/bin/uptime-push`; on the NAS `{{ docker_base_path }}/uptime-push`, `host_vars/nas`, since UGOS's root is an overlay on the eMMC and the borgmatic container sees `docker_base_path` at the same path), `0755 root`: user units (betisier, monica_v4) run it too.

```
uptime-push [--strict] [--agent NAME] <curl-config-file|-> <up|down> [message]
```

- The push URL carries the monitor's token: it is read from a curl config file (`url = "…"`, `0600`, owned by whoever pushes) or from stdin with `-` (`printf 'url = "%s"\n' "$URL" | uptime-push - up "$msg"`), never from a command line (`ps`, `systemctl show`, journald's `_CMDLINE`). curl prints neither the URL nor the file path in its errors.
- curl options: `-q -fsS -o /dev/null --max-time 10 --retry 2 --retry-connrefused --retry-max-time 15 -A <NAME> -G`, `status` and `msg` (default `OK`) through `--data-urlencode`.
- **Worst case**: a hanging Uptime Kuma (connection accepted, no answer) costs 21 s (10 s, 1 s wait, 10 s; a third try would start after the 15 s window). A refused connection: three tries in ~3 s. Measured by the Molecule scenario.
- Exit code: 0 even when the push fails (curl writes the error to stderr), so a down Uptime Kuma never fails the caller; `--strict` returns curl's code instead. 2 on a usage error.

## Callers

Each role below lists `uptime_push` in its `meta/main.yml` `dependencies`, so the helper is installed before the role under the role's own tags, and `resolve_docker_tags.py` / `select_tests.py` redeploy and retest those roles when this one changes.

| Role | Call | Mode |
|---|---|---|
| `borgmatic` | `commands:` hooks of every config (`app.yaml.j2`), `<file> up start` / `up finish` / `down fail` | `\|\| true` (a missing helper never fails a backup) |
| `betisier` | `ExecStartPost` of `betisier-reset.service` | `--strict` (the unit fails) |
| `pangolin` | `ExecStartPost` of `geoipupdate.service` | `--strict` |
| `monica_v4` | `ExecStartPre=-` of `monica_v4_cron.service` | default, `-` prefix |
| `blocky` | `blocky-check.sh`, config on stdin | default (the check's own exit code) |
| `ntfy` | `ntfy-subscribers-check.sh`, config on stdin | default |
| `ssh_login_notify` | the PAM hook, config on stdin, in the background | `--strict` (logs success or failure) |

Not here: the Python scripts (`kdrive_sync`, `nas_proxy`'s cert check, `update_notify`, `vzdump_restore_test`) push with `urllib`, and `.github/workflows/restore-test.yaml` runs on a GitHub runner.

Molecule: scenario `uptime_push` (fake Uptime Kuma on `127.0.0.1:18080`, a black hole on `:18081`).
