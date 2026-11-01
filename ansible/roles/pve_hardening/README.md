# Role `pve_hardening`

Part of `pve.yml` only (by hand, never CI; root without become through `host_vars/pve`). Last role of the play, tag `pve_hardening`, one sub-tag per part so they can be applied one at a time. Findings it closes: network inventory of 2026-10-27 (sshd open to root passwords, PVE firewall disabled, `pve-enterprise` repo without a subscription, unused SDN zone `homelab`). Recovery: `docs/runbooks/proxmox-injoignable-apres-durcissement.md`.

Nothing here is owned by `tofu/proxmox` (it manages the VM, the LXC, the NFS storage and the vzdump job; no firewall or SDN resource), so Ansible is the single writer. Edits made in the web UI to `cluster.fw` are overwritten on the next run.

| Tag | What | Notes |
|---|---|---|
| `pve_apt` | removes `pve-enterprise.sources` / `.list`, writes `proxmox.sources` (`pve-no-subscription`, suite from the facts) | `pve-enterprise.sources` is a `pve-manager` conffile: deleted, dpkg does not bring it back on upgrade |
| `pve_sdn` | deletes the zones of `pve_hardening_sdn_removed_zones` (`homelab`), their vnets and subnets, then `pvesh set /cluster/sdn` (rewrites `/etc/network/interfaces.d/sdn`, `ifreload -a`: the `homelab` bridge and its SNAT rule go, `vmbr0` is untouched); stops and disables `dnsmasq@<zone>` | fails before deleting anything when a guest config under `/etc/pve/nodes` has `bridge=<vnet>` (snapshots included). Idempotent: nothing left, pending or applied (`--running 1`), nothing done; a zone deleted but never applied (run cut short, UI) gets applied |
| `pve_ssh` | `/etc/ssh/sshd_config.d/10-hardening.conf`: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `X11Forwarding no`; `sshd -t`, reload (open sessions stay), then asserts `sshd -T` | asserts first that `/root/.ssh/authorized_keys` (→ `/etc/pve/priv/authorized_keys`) holds a key: Ansible, `tofu/proxmox`'s provider (SSH root through the agent, for snippets) and Sylvain all log in as root by key. The `Include` sits at the top of `sshd_config`, so the drop-in beats the `yes` lines below it. No `MaxAuthTries 3`: an agent offering several keys would hit it |
| `pve_firewall` | `/etc/pve/firewall/cluster.fw`: `enable: 1`, `policy_in: DROP`, `policy_out: ACCEPT`; IN ACCEPT from `pve_hardening_lan_cidr` (192.168.1.0/24) on 22 and 8006, ICMP from the LAN, everything from the NFS server (192.168.1.137: NFS v3 NLM and statd callbacks on dynamic ports); asserts `pve-firewall status` is `enabled/running` | asserts first that the run's SSH client is in the LAN (else the firewall would cut the runner) |

## Firewall scope

- **Host only.** Datacenter rules filter the host's own input. No guest NIC has `firewall=1` (VM 100 `firewall=0`, LXC 200 none; `tofu/proxmox` sets none), so no VM or LXC rule applies. Enabling the firewall does turn on `bridge-nf-call-iptables`: bridged guest traffic now crosses conntrack and `PVEFW-FORWARD`, which drops `INVALID` packets. Symmetric traffic (everything here goes through the Bbox) is unaffected; check the apps after enabling.
- **Who reaches 22/8006**: the PC and every LAN host directly; `pve.internal` (Pangolin client) through the Newt LXC 192.168.1.200; Homepage from the docker VM 192.168.1.216; `tofu/proxmox` from the PC or through `pve.internal`. All LAN sources.
- **Outbound** stays open: NFS to the NAS, Beszel agent to the hub (it dials out, nothing listens), ntfy, apt, ACME.
- **Safety net built into PVE**: on top of these rules PVE adds its own ACCEPT from the `management` IP set (unset here, so `local_network`, which `pve-firewall localnet` detects as 192.168.1.0/24) to 22, 8006, 3128 and 5900-5999. A typo in our rules therefore still leaves 22/8006 open to the LAN. It also means SPICE (3128) and VNC stay reachable from the LAN, as before.
- **Write path**: `/etc/pve` is pmxcfs, which only accepts mode 0640 (0600 under `priv/`); Ansible's atomic write chmods a new file to 0644 and fails. The role renders the file once, keeps a working copy in `/var/lib/pve-hardening/cluster.fw` (the `--diff` shows there), compares the live file with the expected text and writes it with a plain `cat >`. `pve-firewall` picks it up within 10 s.

## Applying (with a rescue session)

From `ansible/`, a root SSH session to 192.168.1.26 left open in another terminal, one part at a time:

```bash
ansible-playbook pve.yml --tags pve_apt,pve_sdn --check --diff
ansible-playbook pve.yml --tags pve_apt,pve_sdn
ansible-playbook pve.yml --tags pve_ssh
ssh -o PasswordAuthentication=no root@192.168.1.26 true   # new session, by key
ansible-playbook pve.yml --tags pve_firewall
ssh root@192.168.1.26 true && curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.1.26:8006/
```

Then `tofu -chdir=tofu/proxmox plan` (API and SSH still work), the Homepage Proxmox card, and an app through Pangolin. If anything is cut: the runbook.

## Test

Molecule scenario `ansible/molecule/pve_hardening/`: a real sshd (root key login works, password login offers only `publickey`), a fake `pvesh`/`pve-firewall` (`files/fake_pve.py`: SDN state in JSON, delete order enforced like the API), a stand-in `dnsmasq@homelab`, and a second pass where a guest uses the vnet: the role must stop before any delete.
