# Role `vzdump_restore_test`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Part of `pve.yml` (row in `docs/conventions/ansible.md`).

`vzdump_restore_test` (tags `vzdump_restore_test,vzdump`: on the 2nd and 16th at 10:00, `vzdump-restore-test.timer` restores the newt LXC's latest vzdump archive to the throwaway id 990 on `local-lvm`, network unplugged then removed and `newt.service` masked before it boots — a second Newt would steal the `proxmox-lxc` tunnel —, checks systemd reaches running/degraded, destroys it, and fully verifies the docker VM's (id 100) archive with `zstd -d | vma verify -`, never restored (190 GiB of disk the host's SSD and memory cannot spare); ids 900-999 reserved, only marked copies created by the run are destroyed; report to ntfy topic `scripts` with `ntfy_scripts_token` and to the push monitor « Test restauration vzdump », `docs/runbooks/test-restauration-vm.md`)
