# Role `vzdump_restore_test`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Part of `pve.yml` (row in `docs/conventions/ansible.md`).

`vzdump_restore_test` (tags `vzdump_restore_test,vzdump`: on the 2nd and 16th at 10:00, `vzdump-restore-test.timer` restores the newt LXC's latest vzdump archive to the throwaway id 990 on `local-lvm`, network unplugged then removed and `newt.service` masked before it boots — a second Newt would steal the `proxmox-lxc` tunnel —, checks systemd reaches running/degraded, destroys it, and fully verifies the docker VM's (id 100) archive with `zstd -d | vma verify -`, never restored (190 GiB of disk the host's SSD and memory cannot spare); ids 900-999 reserved, only marked copies created by the run are destroyed; report to ntfy topic `scripts` with `ntfy_scripts_token` and to the push monitor « Test restauration vzdump », `docs/runbooks/test-restauration-vm.md`)

## Daily check of the nightly backup

`vzdump-freshness.timer` (07:30 every day, same script with `--freshness`) reads the storage index only: the latest archive of each guest must be younger than `vzdump_restore_test_max_age_hours` (26) and above its floor size. Nothing is restored, no lock is taken. It pushes up, or down with the guest at fault, to the « Sauvegarde vzdump » monitor (`tofu/pangolin_config/backup_vzdump.tf`, output `uptime_backup_vzdump_url`, read by `pve.yml` into `vzdump_restore_test_freshness_healthcheck_url`). The 21:00 job has no other alert: its `notification_mode` points at Proxmox's notification system, which has no target declared in this repo.

Order on a first install: apply `tofu/pangolin_config` (creates the monitor), then `ansible-playbook pve.yml --tags vzdump`. With an empty URL the check only writes to the journal (`journalctl -u vzdump-freshness`). `vzdump_restore_test_freshness_enabled: false` stops the timer; pause the monitor too, or it pages after 26 h.
