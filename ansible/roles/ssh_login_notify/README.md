# Role `ssh_login_notify`

Alert on SSH sessions: a `pam_exec` hook in `/etc/pam.d/sshd` pushes the user, the source IP and the key to the host's Uptime Kuma push monitor, which notifies on Telegram (#451). A key of the known list only leaves a low-priority ntfy trace and a journal line. Why, and the accepted risk: [ADR 0027](../../../docs/adr/0027-connexions-ssh-cles-connues.md).

Part of `00-setup.yaml` (`all,!backups,!nas,!pve`, role entry with `become: true`, tags `ssh_login_notify,security`). **By hand only, never by CI**: `resolve_docker_tags.py` prints a notice for this role and deploys nothing. Monitors exist for `local.ssh_login_hosts` of `tofu/pangolin_config/ssh_login_monitors.tf`: docker, flip, newt-lxc, pangolin, pi. The NAS and the Proxmox host have no hook.

## Current behaviour

- PAM line, last of the file: `session optional pam_exec.so quiet <script>`. It takes effect at the next session, with no sshd reload. It relies on `UsePAM`: no variable of this repo overrides devsec's `ssh_use_pam: true`.
- At `open_session`, the script (`/usr/local/sbin/ssh-login-notify`, root) reads its configuration, sends the rest to the background, detached, and exits 0. In the background: type and SHA256 fingerprint of the key from `SSH_AUTH_INFO_0`, key name from the comment of its line in `~/.ssh/authorized_keys` or `authorized_keys2`, then one of the two paths below.
- **Known key** (fingerprint in the list, and public key the only method of the session): journal line `clé connue : …`, then a POST to ntfy, topic `scripts`, `Priority: low`. No push, so no Telegram. A ntfy that fails (22 s at worst) adds a line `échec de la trace ntfy : …` at `auth.warning`, and still no push.
- **Everything else** (other key, other or additional method, unreadable fingerprint, empty list): `uptime-push --strict` (role `uptime_push`, a `meta` dependency) with the URL on stdin; `logger -t ssh-login-notify` records the outcome (a failure at `auth.warning`). A session opened with something other than a public key has a message of its own (« sans clé publique »). A push that fails (21 s at worst, `ansible/roles/uptime_push/README.md`) leaves only that local log line.
- One connection is one PAM session, one notification: `ssh -N` counts, and a `ControlMaster` connection counts once whatever it runs. Only `/etc/pam.d/sshd` is touched, so sessions not opened by sshd do not pass here.
- The monitors are inverted (`upside_down`, Tofu): a push turns one DOWN, which sends the notification with the message; 60 s without a push turns it UP, a second message (the recovery is kept). A monitor already DOWN does not notify again. Known keys no longer push, so a deploy leaves the monitor UP and the next unknown key rings. **What remains**: two pushing sessions less than 60 s apart on one host merge into one alert; the second one is only in the journal and in the monitor's heartbeats.

## Variables

- `ssh_login_notify_push_url`: set by `00-setup.yaml` (`no_log`) from the `uptime_ssh_login_urls` output of `pangolin_config`, by `inventory_hostname`; `tofu/pangolin_config/tests/invariants.tftest.hcl` pins that expression.
- `ssh_login_notify_known_fingerprints`: SHA256 fingerprints (`ssh-keygen -l` format) of the known keys. Role defaults: `keys/github-actions.pub` (the CI) and `keys/perso.pub` (Ansible from the workstation: `ansible_ssh_private_key_file` in `group_vars/all`, `~/.ssh/keepassxc.pub`, the same key as `mise run ssh*` of `ansible/mise.toml` and a plain `ssh`). `android` and `pro` stay on Telegram. Never in `group_vars/all`, whose change redeploys all four playbooks.
- `host_vars/newt-lxc` sets it to `[]`: no key is known there, neither the CI's (the CI never deploys there) nor `perso`, so every login on the LXC, by-hand Ansible runs included, is a Telegram alert. That file is not in the deploy workflow's paths (`test_host_vars_of_a_manual_host_deploy_nothing`). The scenario compares both lists with `keys/` and deploys the empty one.
- `ssh_login_notify_ntfy_url`, `ssh_login_notify_ntfy_topic`, `ssh_login_notify_ntfy_token`: the `scripts` publisher of role `ntfy`, token from the SOPS key `ntfy_scripts_token`, as role `canary` in the same play. Empty token: journal only, a warning at deploy time.
- `ssh_login_notify_enabled`: `false` removes the hook.

## Non-obvious or dangerous

- **The hook must never block a login**: it is `optional`, always exits 0, and everything slow runs detached. The PAM line stays as it is: no `pam_succeed_if`, no `[success=N …]` jump, no `required`. The key file is only read if it is a regular file, since a named pipe or a link to `/dev/zero` would hang `awk`.
- **Empty URL ≠ uninstall.** A host with no URL (not in `local.ssh_login_hosts`, monitors not applied, `pangolin_config` state unreadable, which `00-setup.yaml` tolerates) gets a warning and nothing is touched: a hook already there stays, with its previous configuration. Only `ssh_login_notify_enabled: false` removes it, the PAM line first so that the stack never calls a missing script.
- **Keys are known by fingerprint, never by comment**: whoever is connected can change a comment in `authorized_keys`. The key name in the message comes from that comment, so it is a hint; the fingerprint next to it is the fact.
- **A lost or stolen known key does not ring the phone** except on newt-lxc, and a login with the Ansible key cannot be told from an ad hoc one by Sylvain or Claude (ADR 0027). A replaced key missing from the list rings, which is the safe side.
- `/etc/ssh-login-notify.conf` holds the monitor's token and the ntfy token (`0600 root`, `diff: false`). The script sources it as root and hands the ntfy token to curl on stdin (`--config -`), never on a command line. After a rotation of `ntfy_scripts_token`: `ansible-playbook 00-setup.yaml --tags ssh_login_notify`.

## Testing

`mise run molecule ssh_login_notify` (fake Uptime Kuma and ntfy, real sshd logins, no `security` role applied): the lists against `keys/`, message contents, `ssh -N`, known key (low-priority request, no push, journal line) versus a key borrowing its comment (push, no request), an unknown key right after a known one, `ControlMaster` with three commands, doubtful sessions through the hook called directly (other method, nothing readable, bad key, second factor), newt-lxc's empty list deployed by the role, ntfy refusing, closed, hanging or without a token (login under 5 s, failure journaled, token not in `ps`, no request without a token), login time with a hanging Uptime Kuma and with a named pipe at `authorized_keys2`, login still accepted with a closed port and with a missing script, then the uninstall and its idempotence. **Not covered**: the empty URL, the monitors and their DOWN/UP transitions, the real ntfy and its Pangolin route. On a host: log in, then `journalctl -t ssh-login-notify`.

## Pointers

Lost key or workstation: `docs/runbooks/perte-cle-ou-poste.md` (step on fingerprints). Token rotation: `docs/runbooks/rotation-des-secrets.md`. SSH refused after hardening: `docs/runbooks/ssh-refuse-apres-durcissement.md`. Host table: `docs/conventions/ansible.md`.
