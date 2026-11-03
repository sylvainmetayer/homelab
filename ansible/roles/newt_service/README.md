# Role `newt_service`

Newt as a plain systemd service, without Docker: the binary of the GitHub release, `/etc/newt/env`, `newt.service`. The Docker hosts have the role `newt` (container, `ansible/roles/newt/README.md`).

Part of `lxc.yml` only (tags `newt,setup`), on the Proxmox Newt LXC: site `proxmox-lxc`, the LAN private resources and the CI's way to the home hosts. **By hand only, never by CI**: `resolve_docker_tags.py` prints a notice for this role and deploys nothing.

## Variables

- `newt_service_id` / `newt_service_secret`: empty in the defaults, and the role refuses to run without them. `lxc.yml` sets them (`no_log`) from the `proxmox_lxc_newt_*` outputs of the `tofu/pangolin_config` state, not from SOPS. They land in `/etc/newt/env` (`0600 root`, `diff: false`), never on the command line, where `ps` would show them to the whole container.
- `newt_service_version` is tracked by Renovate, but **`newt_service_sha256` changes by hand**: `get_url` refuses any other file, so a bump without it fails the play.
- `newt_service_binary`, `newt_service_config_dir`: do not change them alone, `vzdump_restore_test_lxc_expect_files` and `_expect_executables` look for those paths in the restored LXC (`ansible/roles/vzdump_restore_test/`).

## Non-obvious or dangerous

- **A restart cuts the tunnel**, hence the CI's access to the LAN and the private resources, until newt reconnects. The handler runs when the binary, the credentials or the unit change. Inferred, not observed: an SSH session of yours going through this site would be cut the same way (see the `flip.internal` rule in `docs/conventions/ansible.md`).
- **Never two Newts with these credentials**: a second one would take the site's tunnel (comment in `vzdump_restore_test`'s defaults, which masks `newt.service` in the restored copy for that reason).
- The unit runs under `DynamicUser` with `CAP_NET_RAW` only (its ICMP tests), `ProtectSystem=strict` and state in `/var/lib/newt`. So the binary must stay world-executable (`0755`): the dynamic user is neither root nor in its group.
- Same version as the role `newt` is the aim, but nothing enforces it: Renovate tracks the GitHub release here and the Docker image there as two dependencies, in two PRs, since the group `pangolin-role-dependencies` selects by file (`ansible/roles/pangolin/**`, `ansible/roles/newt/**`), not this role. Upstream also publishes them at different times. On 2026-11-03, `newt_service_version` is 1.19.0 (since the role's creation, 586886f9) and the image of `ansible/roles/newt/templates/compose.yaml` is 1.19.1 (that group's merge of 2026-11-02, fe870e46): the 1.19.1 image was pushed on 2026-10-27, its GitHub release published only on 2026-11-03 at 20:11 UTC, so no Renovate run could propose it here before (inferred from these dates, Renovate's log not read). Upstream's 1.20.0 is pending on the Dependency Dashboard on both sides, in two branches.
- A fresh LXC only has root: `00-setup.yaml --limit newt-lxc -e ansible_user=root` first (top of `lxc.yml`).

## Testing

`mise run molecule newt_service` downloads the real binary (checksum verified). With fake credentials newt connects to nothing and restarts in a loop, so the verify checks the installation (checksum, modes, no secret in the unit, unit enabled), **not the connection**. On the LXC: `systemctl status newt`, `journalctl -u newt`, and the site's state in Pangolin.

## Pointers

Playbook row: `docs/conventions/ansible.md`. The site and its private resources: `tofu/pangolin_config/README.md`. The LXC itself: `tofu/proxmox/README.md`. Its SSH when locked out: `docs/runbooks/ssh-refuse-apres-durcissement.md`.
