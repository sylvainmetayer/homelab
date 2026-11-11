# Role `thin_pool_check`

Part of `pve.yml` (by hand, never CI).

`thin_pool_check` (tag `thin_pool_check`): every 6 hours (at :15 of 03, 09, 15 and 21 h: the 21:15 pass falls inside the 21:00 vzdump, when its fleecing image fills the pool, `tofu/proxmox/backup.tf`) `thin-pool-check.timer` runs `files/thin-pool-check.sh` (root, POSIX sh), which reads the LVM thin pools with `lvs` and pushes to the Uptime Kuma monitor « Thin pool Proxmox » (`tofu/pangolin_config/cron_thin_pool.tf`, output `uptime_cron_pve_thin_pool_url`, `set_fact`'d by `pve.yml`): `up` with the percentages, `down` when the **data or the metadata** of a pool reaches `thin_pool_check_threshold` (85 %), when `lvs` fails or finds no pool. A `down` pages at once (Telegram and ntfy, like the other push monitors); a missing push pages after one day (three missed passes).

Why: Beszel's agent on `pve` measures `/` (`pve-root`), not `local-lvm`. A full thin pool freezes the docker VM and the newt LXC, and Beszel's 85 % disk alert never sees it (capacity report of 2026-11-05). Measured 2026-11-07: data 23.85 %, metadata 1.32 % (pool `pve/data`, 349 GiB, `vm-100-disk-0` 190 GiB at 42 %).

No ntfy token and no SOPS key: the push URL comes from the Tofu state, the alert goes through Uptime Kuma. The URL sits in `<thin_pool_check_dir>/thin-pool-check.env` (`0600`), never on a command line.

If it rings: grow the pool or free space (`lvs -a`, `docs/runbooks/sante-des-disques.md`); never `lvextend` a thin volume past what the pool can hold. A thin pool at 100 % freezes its volumes.

Apply by hand after `tofu apply` of `tofu/pangolin_config`: `ansible-playbook pve.yml --tags thin_pool_check`, from `ansible/`.

Tests: `ansible/molecule/thin_pool_check` (fake `lvs`: under, over on data, over on metadata, `lvs` failing, no pool).
