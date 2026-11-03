# Role `ssh_login_notify`

Alert on every SSH session: a `pam_exec` hook in `/etc/pam.d/sshd` pushes the user, the source IP and the key to the host's Uptime Kuma push monitor, which notifies on Telegram (#451).

Part of `00-setup.yaml` (`all,!backups,!nas,!pve`, role entry with `become: true`, tags `ssh_login_notify,security`). **By hand only, never by CI**: `resolve_docker_tags.py` prints a notice for this role and deploys nothing. Monitors exist for `local.ssh_login_hosts` of `tofu/pangolin_config/ssh_login_monitors.tf`: docker, flip, newt-lxc, pangolin, pi. The NAS and the Proxmox host have no hook.

## Current behaviour

- PAM line, last of the file: `session optional pam_exec.so quiet <script>`. It takes effect at the next session, with no sshd reload. It relies on `UsePAM`: no variable of this repo overrides devsec's `ssh_use_pam: true`.
- At `open_session`, the script (`/usr/local/sbin/ssh-login-notify`, root) reads its configuration, sends the rest to the background, detached, and exits 0. In the background: type and SHA256 fingerprint of the key from `SSH_AUTH_INFO_0`, silent exit if the fingerprint is ignored, key name from the comment of its line in `~/.ssh/authorized_keys` or `authorized_keys2`, then `uptime-push --strict` (role `uptime_push`, a `meta` dependency) with the URL on stdin. `logger -t ssh-login-notify` records the outcome (a failure at `auth.warning`).
- A session opened with something other than a public key has a message of its own (« sans clé publique ») and is never silenced. A connection without a shell (`ssh -N`) notifies as well. Only `/etc/pam.d/sshd` is touched, so sessions not opened by sshd do not pass here.
- The monitors are inverted (`upside_down`, Tofu): a push turns one DOWN, which sends the notification with the message; 60 s without a push turns it UP, a second message. So sessions less than 60 s apart on one host merge into one alert.
- A push that fails (21 s at worst, `ansible/roles/uptime_push/README.md`) leaves only that local log line.

## Variables

- `ssh_login_notify_push_url`: set by `00-setup.yaml` (`no_log`) from the `uptime_ssh_login_urls` output of `pangolin_config`, by `inventory_hostname`; `tofu/pangolin_config/tests/invariants.tftest.hcl` pins that expression.
- `ssh_login_notify_ignored_fingerprints`: SHA256 fingerprints (`ssh-keygen -l` format) of the keys that stay silent. Empty, and set by no `host_vars` or `group_vars`: everything notifies, the CI's key included.
- `ssh_login_notify_enabled`: `false` removes the hook.

## Non-obvious or dangerous

- **The hook must never block a login**: it is `optional`, always exits 0, and everything slow runs detached. The key file is only read if it is a regular file, since a named pipe or a link to `/dev/zero` would hang `awk`.
- **Empty URL ≠ uninstall.** A host with no URL (not in `local.ssh_login_hosts`, monitors not applied, `pangolin_config` state unreadable, which `00-setup.yaml` tolerates) gets a warning and nothing is touched: a hook already there stays, with its previous configuration. Only `ssh_login_notify_enabled: false` removes it, the PAM line first so that the stack never calls a missing script.
- **Keys are silenced by fingerprint, never by comment**: whoever is connected can change a comment in `authorized_keys`. The key name in the message comes from that comment, so it is a hint; the fingerprint next to it is the fact.
- `/etc/ssh-login-notify.conf` holds the monitor's token (`0600 root`, `diff: false`). The script sources it as root.

## Testing

`mise run molecule ssh_login_notify` (fake Uptime Kuma, real sshd logins, no `security` role applied): message contents, `ssh -N`, ignored fingerprint versus a key borrowing its comment, login time with a hanging Uptime Kuma and with a named pipe at `authorized_keys2`, login still accepted with a closed port and with a missing script, then the uninstall and its idempotence. **Not covered**: the « sans clé publique » message (key logins only), the empty URL, the monitors. On a host: log in, then `journalctl -t ssh-login-notify`.

## Pointers

Lost key or workstation: `docs/runbooks/perte-cle-ou-poste.md` (step on fingerprints). SSH refused after hardening: `docs/runbooks/ssh-refuse-apres-durcissement.md`. Host table: `docs/conventions/ansible.md`.
