# Copilot Instructions - Homelab Infrastructure

## Architecture Overview

This is a multi-environment homelab infrastructure project using:
- **OpenTofu** (Terraform fork) for infrastructure provisioning
- **Packer** for VM image creation
- **Ansible** for configuration management
- **SOPS + Age** for secrets management

Two deployment targets:
1. **Pangolin** - Hetzner Cloud-based zero-trust infrastructure
2. **Proxmox** - Local homelab VMs/LXC containers

## Critical Workflows

### Task Runner: mise
All commands use `mise` (NOT `make`). Key tasks:
```bash
mise run init           # Tofu init (Pangolin)
mise run plan           # Tofu plan (Pangolin)
mise run apply          # Tofu apply (Pangolin)
mise run packer-build   # Build Pangolin image
mise run ansible-run    # Run Ansible playbook
mise run lint           # Validate Tofu configs
```

For Proxmox, use `-proxmox` suffix: `mise run init-proxmox`, `mise run plan-proxmox`, etc.

### Secrets Management
Secrets stored in `secrets.sops.yaml` (encrypted with Age). Key pattern:
```yaml
# Load secrets in Ansible playbooks
community.sops.load_vars:
  file: "{{ playbook_dir }}/secrets.sops.yaml"
  expressions: evaluate-on-load
```

**IMPORTANT**: Export `SOPS_AGE_KEY` environment variable before operations.
Generate password hashes: `mise run generate_password "<password>"`

### Ansible Patterns

Three main playbooks:
- `00-setup.yaml` - Initial host setup, user creation, base packages
- `01-services.yaml` - Services for finch host (personal workstation)
- `02-photos.yaml` - Raspberry Pi photo services
- `site.yml` - Proxmox VMs configuration (docker services)

**Docker Services Pattern**: All services use systemd user units via `docker_service` role:
- Service definition: `dc@<service-name>.service`
- Enable linger: `loginctl enable-linger $USER`
- Template location: `roles/docker_service/templates/dc@.service.j2`

Roles split by host:
- `finch`: Personal workstation (nextcloud, wiki, rss, monica, etc.)
- `docker`: Proxmox VM running Docker services (newt, echo, rss, betisier)
- `pi`: Raspberry Pi (photoprism backups)

### Infrastructure Provisioning

**Backend**: S3-compatible object storage (not standard AWS):
```hcl
backend "s3" {
  endpoints = { s3 = "https://nbg1.your-objectstorage.com" }
  bucket = "homelab-state"
}
```

**Packer Image**: Pre-baked Debian 13 with Docker, Pangolin installer, hardening (fail2ban, UFW, sysctl).

**Tofu modules**:
- `tofu/pangolin/`: Hetzner Cloud server with Pangolin Zero Trust
- `tofu/proxmox/`: Proxmox VMs (Docker VM + Newt LXC container)

## Project Conventions

### File Organization
- Ansible roles: `ansible/roles/<service>/` with `tasks/`, `templates/`, `defaults/`, `handlers/`
- Host-specific vars: `ansible/host_vars/<hostname>/` (not `group_vars/<hostname>`)
- Ansible collections: `ansible/collections/ansible_collections/`
- Galaxy roles: `ansible/galaxy_roles/`

### Ansible Variable Override Warning
From codebase: "WARNING: You cannot override variables with community.sops.load_vars, make sure variable is not defined before."

### Naming Patterns
- Services: lowercase, descriptive (betisier, newt, echo, rss)
- Systemd units: `dc@<service-name>.service` for Docker Compose services
- Tofu files: descriptive (`proxmox_docker_vm.tf`, `proxmox_newt_lxc.tf`)

## Tools & Dependencies

Required tools (managed by `mise.toml`):
- `opentofu` 1.11.2
- `packer` latest
- `sops` latest
- `age` latest
- `pangolin` CLI (fosrl/cli) 0.2.1

Ansible collections (from `requirements.yml`):
- `community.sops` - Secrets decryption
- `devsec.hardening` - SSH/nginx hardening
- `sylvainmetayer.workstation` - Workstation configuration

## Debugging

- Ansible logs: `ansible/run.log`
- Ansible facts cache: `ansible/facts/`
- Check mode: `mise run ansible-check`
- Verbose: Add `-v`, `-vv`, or `-vvv` to ansible commands
- rclone: `sudo -i rclone ls backup:`
- borgmatic : `sudo -i borgmatic --list --config /etc/borgmatic.d/<config>.yaml`
- borgmatic info: `sudo -i borgmatic --info`

## Key External Dependencies

- Hetzner Cloud (Pangolin deployment)
- Proxmox VE (local homelab)
- S3-compatible object storage (Tofu state)
- Cloudflare DNS (configured in `tofu/pangolin/dns.tf`)
- Pangolin Zero Trust platform (for secure access)

## Notes
- Pangolin newt must be in same Docker network as containers for socket proxy access
- SSH access only on local network for Raspberry Pi
- Cloud-init cleaned in Packer image to allow reconfiguration
