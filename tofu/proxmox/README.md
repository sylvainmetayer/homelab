# tofu/proxmox

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

`tofu/proxmox/` — Proxmox VE provider: the Docker VM (`proxmox_docker_vm.tf`, read back as inventory by `ansible/inventory/proxmox.py`) and the Newt LXC container (`proxmox_newt_lxc.tf`; static in `inventory/hosts`, configured by `ansible/lxc.yml`), and their nightly vzdump job (`backup.tf`: `proxmox_backup_job`, imported from the job created in the UI) onto the NFS storage `nas-backup` (export `/volume1/pve-backup` of `host_vars/nas`, client the Proxmox host only; the test pins that contract), never onto `local`, the host's root.
