# tofu/pangolin

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

`tofu/pangolin/` — Hetzner Cloud provider: the Pangolin VM, the flip VM (private network only) and the network route that makes Pangolin its NAT gateway, and Hetzner Storage Box config (see `STORAGE_BOX_SETUP.md` there for the manual setup steps SSH/rsync require). The state bucket is not here but in `tofu/s3_state/` (OVH Object Storage).

## The Pangolin server: image, backups, rebuild

The running Pangolin server was created from an old Packer snapshot (Packer has since been removed from the repo). `image` is in the `ignore_changes` of `hcloud_server.pangolin` (`tofu/pangolin/pangolin.tf`), so the plan stays clean. Its Hetzner backups are on (`backups = true`, 7 daily images, deleted with the server): if the server still exists and was not compromised, restore yesterday's image first (same IP and host key), then replay `pangolin.yaml` and plan `pangolin_config`. Otherwise a rebuild starts from plain `debian-13` + `user_data.yaml` (user `sylvain` only), then `00-setup.yaml` and `pangolin.yaml`, then a restore of `/opt/pangolin` (config, SQLite DB, Let's Encrypt certificates) from its Borg repository. A rebuilt host has a new SSH host key: read it on the host (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, Hetzner console) and replace its line in `ansible/known_hosts`, never through `ssh-keyscan` across the network — Ansible (`ansible.cfg` `ssh_args`, `StrictHostKeyChecking=yes`), the bastion jump of `hetzner.py` (a `ProxyCommand`, so the jump checks the same file) and the CI all refuse any other key.
