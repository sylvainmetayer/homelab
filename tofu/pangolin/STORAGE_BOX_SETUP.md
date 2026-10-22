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
mkdir -p backup/{betisier,monica_v4,wiki,nextcloud,rss,immich,pangolin}
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

### 7. Per-host subaccounts and keys

Hosts never use the main account. `storage_box_subaccounts.tf` creates one
subaccount per backed-up host, whose home is `backup/<host>`; copy the
`storage_box_subaccounts` output into the SOPS key
`backup_storage_box_subaccounts` (`ansible/secrets.sops.yaml`). The borgmatic
role generates root's key on each host (`/root/.ssh/borgmatic_storage_box_ed25519`),
then `ansible/backup.yaml` creates `backup/<host>/.ssh` and uploads that key as
the subaccount's `authorized_keys`. The main account keeps the personal keys
only (perso, pro, android), in its own `.ssh/authorized_keys`.

Migration from the former shared key: removing it from `ssh_keys` in
`storage_box.tf` revokes nothing (`ignore_changes`, the API does not edit the
list). Remove its line by hand from the main account's `.ssh/authorized_keys`
(download it with `scp -P 23`, delete the `tls_private_key.storage_box` key,
upload it back), otherwise the old private key, still in the SOPS history and
the former clear-text `tofu/pangolin` state, keeps full access to every
repository.

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

Seen from the main account (each subaccount sees its own folder as `/`):
```
backup/
├── docker/      wiki/, nextcloud/, rss/, paperless/, trek/, karakeep/, …
├── pi/          immich/
├── pangolin/    pangolin/
└── flip/        flip_planning/, demo_planning/
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
