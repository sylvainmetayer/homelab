# Hetzner Storage Box Configuration

## Overview

The Hetzner Storage Box 1TB is used as a remote backup destination for all Borg/Borgmatic backups, replacing the S3 bucket for better direct storage management.

**Hostname**: `u<ID>.your-storagebox.de` (example: `u123456.your-storagebox.de`)
**Username**: `u<ID>` (example: `u123456`)
**Protocol**: SSH/SFTP
**Port**: 22

## Setup Steps

### 1. Create Storage Box via Hetzner Robot

1. Log in to [Hetzner Robot](https://robot.hetzner.com/)
2. Navigate to **Products** → **Storage Boxes**
3. Click **Order a Storage Box**
4. Select **Storage Box 1 TB**
5. Choose the location (recommend: same as Pangolin server for latency)
6. Complete the order

### 2. Initial Configuration

After creation, you'll receive:
- Hostname: `u<ID>.your-storagebox.de`
- SSH Username: `u<ID>`
- Password: (auto-generated, available in Robot dashboard)

### 3. Generate SSH Key Pair (on Pangolin server)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/storagebox -C "homelab-backups"
```

### 4. Add SSH Public Key to Storage Box

```bash
scp ~/.ssh/storagebox.pub u<ID>@u<ID>.your-storagebox.de:.ssh/authorized_keys
```

Or manually via Hetzner Robot:
1. Go to **Subaccounts** → **+New**
2. Create SSH key entry with public key content

### 5. Create Backup Directories

```bash
ssh -i ~/.ssh/storagebox u<ID>@u<ID>.your-storagebox.de << 'EOF'
mkdir -p backup/{betisier,monica_v4,wiki,nextcloud,rss,immich,photoprism,pangolin}
chmod 700 backup
EOF
```

### 6. Update Tofu Configuration

Edit `terraform.tfvars`:
```hcl
storage_box_enabled  = true
storage_box_hostname = "u123456.your-storagebox.de"  # Replace with actual ID
storage_box_username = "u123456"                     # Replace with actual ID
```

### 7. Update Ansible Variables

Edit `ansible/group_vars/all/variables.yml`:
```yaml
backup_storage_box_hostname: "u123456.your-storagebox.de"  # Replace with actual ID
backup_storage_box_username: "u123456"                     # Replace with actual ID
backup_storage_box_path: "backup"
```

### 8. SSH Key Distribution

Place the private SSH key on backup hosts:
- **Docker host**: `/root/.ssh/storagebox`
- **Raspberry Pi**: `/root/.ssh/storagebox`
- **Pangolin**: `/root/.ssh/storagebox` (optional, for testing)

**Important**: Keep this key secure and do not commit to version control.

## Borg Repository Initialization

Borgmatic will automatically initialize repositories on first run. However, you can pre-initialize manually:

```bash
ssh -i ~/.ssh/storagebox root@<docker-host> << 'EOF'
export BORG_REPO="ssh://u<ID>@u<ID>.your-storagebox.de:22/backup/betisier"
export BORG_PASSPHRASE="<encryption_passphrase>"
/root/.local/bin/borg repo create --encryption=repokey-blake2
EOF
```

## Bandwidth & Quotas

- **Monthly bandwidth**: Included in subscription
- **Disk quota**: 1 TB
- **INodes**: ~27 million

Monitor usage:
```bash
ssh -i ~/.ssh/storagebox u<ID>@u<ID>.your-storagebox.de quota
```

## Backup Paths

After setup, backups will be stored at:
```
ssh://u<ID>@u<ID>.your-storagebox.de:22/backup/
├── betisier/
├── monica_v4/
├── wiki/
├── nextcloud/
├── rss/
├── immich/
├── photoprism/
└── pangolin/
```

## Verification

Test SSH connectivity from Docker host:
```bash
ssh -i ~/.ssh/storagebox -p 22 u<ID>@u<ID>.your-storagebox.de ls -la backup/
```

Test Borg connectivity:
```bash
export BORG_REPO="ssh://u<ID>@u<ID>.your-storagebox.de:22/backup/betisier"
/root/.local/bin/borg list
```

## Decommissioning

To remove backups from Storage Box:
```bash
ssh -i ~/.ssh/storagebox u<ID>@u<ID>.your-storagebox.de rm -rf backup/
```

To cancel the Storage Box, use the Hetzner Robot interface.

## References

- [Hetzner Storage Box Documentation](https://docs.hetzner.cloud/robot/storage-box/)
- [Borg SSH Configuration](https://borgbackup.readthedocs.io/en/stable/usage/serve.html)
- [Borgmatic Remote Repository Guide](https://torsion.org/borgmatic/docs/reference/configuration/#archive-upload)
