# Role `smart_check`

Part of `pve.yml` (by hand), `pi.yml` (CI) and `nas.yml` (by hand).

`smart_check` (tag `smart_check`): every Monday morning `smart-check.timer` runs `files/smart_check.py` (root, stdlib only), which reads each disk with `smartctl -j -i -H -A` (`-i`: without it `rotation_rate`, model and serial number are absent, and the SSD wear check never runs), applies the thresholds of `docs/runbooks/sante-des-disques.md`, and publishes to ntfy topic `scripts` (`ntfy_scripts_token`, same publisher as `update_notify`) **only when a finding rises**. Beszel only alerts on the global `FAILED` verdict; this covers what it does not.

| Disk | Finding | Priority |
|---|---|---|
| any | verdict `FAILED` | 5 |
| hard disk | 197 `Current_Pending_Sector` or 198 `Offline_Uncorrectable` above 0 | 5 |
| hard disk | 5 `Reallocated_Sector_Ct` above 0, 199 `UDMA_CRC_Error_Count` above 0 | 4 |
| SSD (`rotation_rate` 0) | normalised value of 177, 173, 169, 202, 231, 233 or 232 below 20 (below 10) | 4 (5) |
| NVMe | `Percentage Used` above 80 | 4 |
| NVMe | `Available Spare` below 20, `Media and Data Integrity Errors` above 0 | 5 |

- **Rise, not every pass.** Each finding keeps its highest announced level (raw value of a counter, or 1/2 for a threshold) in `<smart_check_dir>/state.json`, per serial number (a USB disk renamed `sdX` keeps its history). A finding is announced when it exceeds that level, the first time included; the message then says `(annoncé à N)`. `sdc` of the NAS (known failing, kept with nothing counting on it) therefore rings once, then again only if a counter grows. Findings still present stay in the summary pushed to Uptime Kuma every week (`2 constat(s) : …`), visible in the monitor. A counter that falls but stays above 0 and rises back below its high-water mark does not ring; a finding that disappears is forgotten (its relapse rings again, and a replaced disk of the same name starts from zero). A crash of the script (unexpected JSON) pushes `down` too. The state is written only after the publication succeeded: a failed publication is redone next pass. A lost state file (reset of UGOS) costs one repeated alert.
- **A disk that cannot be read** (USB bridge without SMART passthrough, permission) pushes `down` after the readable disks were checked and published: silence must not pass for health.
- Every pass pushes up (summary) or down to the host's monitor « S.M.A.R.T. <host> » (`tofu/pangolin_config/cron_smart.tf`, one `for_each` entry per host, output `uptime_cron_<host>_smart_url`, `set_fact`'d by each playbook in the literal form `tofu/pangolin_config/tests/invariants.tftest.hcl` greps for). No SOPS key: the ntfy token is the existing `ntfy_scripts_token` and the push URL comes from the Tofu state.
- Disks are per host, in the role entry's `vars:` (`smart_check_devices`, `{ path, type }`): `pve` `/dev/sda`; `pi` `/dev/sda` with `type: sntrealtek` (the NVMe sits behind a Realtek USB bridge); `nas` `sda` and `sdb` (`sdc`, the USB disk, is not listed: it dropped off the USB bus on 2026-11-05 and a missing disk pushes `down` every week; once plugged back, add `{ path: /dev/sdc }` in `nas.yml`). The state is keyed by serial number (by path when a `smartctl` gives none). `smartctl` comes from apt (`smart_check_install_smartmontools`, on for `pve` which has it and for the Pi which does not), not on the NAS.

## NAS (manual)

`nas.yml` is never run by CI: after the merge, `ansible-playbook nas.yml --tags smart_check` by hand, from `ansible/`. The role installs nothing there (UGOS ships `smartctl`) and keeps script, environment file and state under `docker_base_path/smart-check` (UGOS's root is an overlay on the eMMC); only the unit files go to `/etc/systemd/system`, like `kdrive-sync`. If `sdc` answers nothing without `-d` once plugged back, set `type: sat` on its entry.

Tests: `ansible/molecule/smart_check` (real unit under systemd, fake `smartctl`, ntfy and Uptime Kuma; the script's own unit tests).
