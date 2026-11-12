# tofu/pangolin

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

`tofu/pangolin/` — Hetzner Cloud provider: the Pangolin VM, the flip VM (private network only) and the network route that makes Pangolin its NAT gateway, and the Hetzner Storage Box with its per-host and read-only subaccounts (`STORAGE_BOX_SETUP.md`: accounts, keys, repositories). The state bucket is not here but in `tofu/s3_state/` (OVH Object Storage).

flip stays without a public IPv4 on purpose (NAT and SSH jump through Pangolin, Pangolin as its single point of failure): [ADR 0019](../../docs/adr/0019-flip-sans-ipv4-publique.md).

## The Pangolin server: image, backups, rebuild

The running Pangolin server was created from an old Packer snapshot (Packer has since been removed from the repo). `image` is in the `ignore_changes` of `hcloud_server.pangolin` (`tofu/pangolin/pangolin.tf`), so the plan stays clean. Its Hetzner backups are on (`backups = true`, 7 daily images, deleted with the server): if the server still exists and was not compromised, restore yesterday's image first (same IP and host key), then replay `pangolin.yaml` and plan `pangolin_config`. Otherwise a rebuild starts from plain `debian-13` + `user_data.yaml` (user `sylvain` only), then `00-setup.yaml` and `pangolin.yaml`, then a restore of `/opt/pangolin` (config, SQLite DB, Let's Encrypt certificates) from its Borg repository. A rebuilt host has a new SSH host key: read it on the host (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, Hetzner console) and replace its line in `ansible/known_hosts`, never through `ssh-keyscan` across the network — Ansible (`ansible.cfg` `ssh_args`, `StrictHostKeyChecking=yes`), the bastion jump of `hetzner.py` (a `ProxyCommand`, so the jump checks the same file) and the CI all refuse any other key.

## The throwaway docker VM (`drill.tf`)

A copy of the Proxmox docker VM on a Hetzner Cloud server, for the rebuild drill and as a provisional host after a disaster: `docs/runbooks/reconstruction-vm-docker.md`. **Off by default** (`count = 0`): `enabled` is only ever set with `-var 'drill={enabled=true,allowed_ssh_cidrs=["<your IP>/32"]}'`, never in `terraform.tfvars`, so an ordinary apply destroys it. It creates three resources (host key, firewall, server) and touches nothing else: no private network (so no Pangolin, flip or NAT), IPv4 only, `fsn1` (the Storage Box's datacenter), label `role=drill` (`hetzner.py` makes it the Ansible group `drill`, nothing else), no Hetzner backups. The firewall opens SSH only, from the given addresses (never `0.0.0.0/0`, validated), and lets out only DNS, NTP, 80, 443 and 23 (the Storage Box): no SMTP, IMAP or SSH, so a restored app cannot mail anyone with the real credentials. The ed25519 host key is generated here and injected by cloud-init (`user_data_drill.yaml`): the `drill_known_hosts_line` output goes to the git-ignored `ansible/known_hosts.drill`, no `ssh-keyscan`. Server type `cx53` (16 vCPU, 32 GiB, 320 GB; check the hourly price in the console first). Tests: `tests/drill.tftest.hcl`.

## The throwaway solver bench (`bench.tf`)

Servers to measure the Flip Planning solver on other CPU types than flip's, one per entry of `server_types` (each type once), named `flip-bench-<type>`. **Off by default** (`count = 0`): `enabled` is only ever set with `-var 'bench={enabled=true,server_types=["cx23","ccx13"]}'`, never in `terraform.tfvars`, so an ordinary apply destroys them. Same shape as flip: private network only (10.0.1.30 and up), no public IP, SSH through the bastion; no Pangolin resource, no Newt, no Hetzner backups. Label `role=bench`: `hetzner.py` makes it the Ansible group `bench` and nothing else, and no playbook targets it (`00-setup.yaml` excludes it; `nat_client` is therefore not applied). The ed25519 host keys are generated here and injected by cloud-init: the `bench_known_hosts_lines` output goes to the git-ignored `ansible/known_hosts.bench`, no `ssh-keyscan`. Tests: `tests/bench.tftest.hcl`.

They receive a **copy of the production database** (real personal data), and a Hetzner firewall does not apply to the private network, so the isolation is on the host, laid by cloud-init (`user_data_bench.yaml`) before anything is deployed:

- nftables, default drop on input, output and forward: SSH in from the bastion only; out, DNS, NTP and HTTP(S) only, **containers included** — no SMTP, IMAP or SSH, and nothing towards the private network (flip, Pangolin's private ports);
- the default route and the resolvers through Pangolin's NAT (what `nat_client` does on flip), re-laid every 30 s by `bench-nat.timer`.

Checked on a real server: HTTPS out, 587/465/25, outgoing SSH, flip and Pangolin's private address all closed, from the host and from a container. The copy itself runs with mail mocked, webhooks and every scheduled job off and its edition deactivated — a second guard, by hand, behind the firewall.

**Destroying is part of the measure**: `tofu apply` with no `-var bench`, then `tofu state list` shows no `bench` resource and the Hetzner console no `flip-bench-*` server; remove `ansible/known_hosts.bench`.
