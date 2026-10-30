# Hetzner Storage Box Configuration

## Overview

One Hetzner Storage Box (BX11, 1 TB, `fsn1`) holds every Borg repository of
the homelab. It is declared in this module, not ordered by hand:
`storage_box.tf` (`hcloud_storage_box.backups`, `delete_protection` plus
`prevent_destroy`, 9 daily snapshots at 03:00 UTC that no subaccount can
delete) and `storage_box_subaccounts.tf` (one subaccount per backed-up host).

Borg talks SSH on **port 23** (`ssh_command: ssh -i … -p 23` in the shared
borgmatic template); port 22 of a Storage Box is SFTP only.

## Accounts

- **Main account**: the personal keys only (`keys/perso.pub`, `pro.pub`,
  `android.pub`), set at creation. The API cannot edit that list
  (`ignore_changes = [ssh_keys]`): the real list is the main account's
  `.ssh/authorized_keys`, edited by hand (`scp -P 23`).
- **One subaccount per host** (`backup-<host>`, home `backup/<host>`, for
  `local.backup_hosts`: docker, pi, pangolin, flip, nas). Root on one host can
  neither read nor delete another host's repositories. Copy the
  `storage_box_subaccounts` output into the SOPS key
  `backup_storage_box_subaccounts` (`ansible/secrets.sops.yaml`). The borgmatic
  role generates root's key on each host (`/root/.ssh/borgmatic_storage_box_ed25519`;
  on the NAS under `/volume1/docker/borgmatic/ssh/`), then `ansible/backup.yaml`
  creates `backup/<host>/.ssh` and uploads that key as the subaccount's
  `authorized_keys`.
- **`restore-test`**, read-only, home `backup/`: the GitHub Actions restore
  test (`.github/restore-test/README.md`). Its key is the
  `storage_box_restore_test_ssh_public_key` output, uploaded into
  `backup/.ssh/authorized_keys` by `ansible/backup.yaml`.

Adding a host: add it to `local.backup_hosts` here, to
`backup_storage_box_hosts` (`ansible/host_vars/backups/variables.yaml`), to
the `hosts:` of the first play of `ansible/backup.yaml` (which reads the keys;
otherwise its assert refuses to upload any) and to the SOPS key, set `backup_storage_box_subaccount` in its `host_vars`, run its
playbook with `--tags setup` (key generated, no app yet), then `backup.yaml`,
then the full playbook.

## Repositories

Nothing to create per app: borgmatic's `repo-create` (run by
`ansible/roles/borgmatic/tasks/app.yml` at deploy time) creates each
repository (`repokey-blake2`, passphrase `backup_passphrase`) in the host's
folder. Seen from the main account (each subaccount sees its own folder as
`/`):

```
backup/
├── docker/      wiki/, nextcloud/, rss/, paperless/, trek/, karakeep/, …
├── pi/          immich/
├── pangolin/    pangolin/
├── flip/        flip_planning/, demo_planning/
└── nas/         jellyfin/
```

## Quota

The weekly `storage-box-quota.yaml` workflow reads the usage (data and
snapshots) through the Hetzner API and pushes down to the `Storage Box`
Uptime Kuma monitor at 80 % or more (`docs/conventions/ci.md`).

## Verification

From a backed-up host but the NAS, as root (`rss` lives on the docker host:
use one of the host's own configs elsewhere):

```bash
sudo ssh backup_storage_box ls                                   # the subaccount answers
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml list
```

The NAS has no `backup_storage_box` alias and runs borgmatic through its
wrapper (`/volume1/docker/borgmatic/borgmatic`, configs under
`/volume1/docker/borgmatic/borgmatic.d/`). Failures, restores and the NAS's
paths: `docs/runbooks/sauvegarde-et-restauration.md`.

## References

- [Hetzner Storage Box documentation](https://docs.hetzner.com/storage/storage-box/)
- [Borg SSH configuration](https://borgbackup.readthedocs.io/en/stable/usage/serve.html)
