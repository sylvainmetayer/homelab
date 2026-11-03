# Role `host_tuning`

Memory and journal settings of a Docker host: a zram swap, optionally a disk swap behind it, a capped persistent journal and, on the Pi, extra kernel parameters.

Part of `docker.yml`, `pi.yml` and `flip.yml` (tags `tuning,setup`; a merge changing the role deploys tag `tuning` on those three). Not on Pangolin, the NAS, the LXC or the Proxmox host. The role entries have no `become`: each task asks for it.

- **zram** (`zram-tools`, 2 GiB zstd by default): a safety net against overcommit. Without swap, an overflow lets the host's OOM killer kill a random container, and zram does not write to the entry-level SATA SSD.
- **Disk swap** (`dphys-swapfile`, `/var/swap`): overflow behind zram, off unless `host_tuning_disk_swap_size_mb` is above 0. Its negative default priority means it only serves once zram is full.
- **Journal** (`/etc/systemd/journald.conf.d/50-size.conf`): `Storage=persistent` and `SystemMaxUse` (500M). `docker compose up` run attached sends every container's logs to journald, which grew to 3.6 GB. On the Pi this drop-in also beats the `Storage=volatile` of `raspberrypi-sys-mods`.
- **Kernel command line**: `host_tuning_kernel_cmdline_params` appended to `host_tuning_kernel_cmdline_path` (`/boot/firmware/cmdline.txt`), only for a parameter not already there as a whole word. Empty on every host but the Pi.

Only `host_vars/pi` overrides this role: `host_tuning_disk_swap_size_mb: 4096` and `cgroup_enable=memory` (the Pi 4 firmware puts `cgroup_disable=memory` in front of `cmdline.txt`: no memory controller, so Docker ignores `mem_limit`; #846).

## Non-obvious or dangerous

- **A broken `cmdline.txt` keeps the Pi from booting.** The role asserts a single non-empty line before touching it, and keeps `cmdline.txt.orig` (written once, never overwritten: the version from before the first pass), to restore from the disk plugged into another machine. No `backup: true`: its file name holds `:`, refused by the FAT partition. FAT also refuses a chmod to anything else than its mount's rights, hence `mode: preserve` on the copy.
- **The Pi reboots by itself.** The role never reboots, but as long as `/proc/cmdline` lacks a parameter, each run writes `/var/run/reboot-required`, and unattended-upgrades (role `security`, `Automatic-Reboot`) then reboots at `security_unattended_reboot_time` (05:30 on the Pi). The flag follows the running kernel, not the file edit, so a play failing halfway does not lose the reboot.
- **zram size is compared live.** The package's postinst starts the service at 50 % of the RAM before the template lands, and a plain restart does not resize an initialised device: each run reads `/sys/block/zram0/disksize` and forces the handler on a difference. The handler `swapoff`s the live device and resets it through sysfs, flushed before the `state: started` task, which would fail on a broken device. Its comments say why neither `zramswap stop` nor `zramctl --reset` works; read them before simplifying it.
- **`host_tuning_disk_swap_size_mb: 0` means "leave alone"**, not "remove": an existing swap file stays. A changed size runs the `dphys-swapfile` handler at the end of the play (swapoff, recreate, swapon); the service task stays `started`, never `restarted`.

## Testing

`mise run molecule host_tuning` loads `host_vars/pi`, so every branch runs, but on simulations: zram is a kernel module of the runner's kernel, so `prepare.yml` shadows `/sys/block` with a tmpfs and replaces `zramswap`, `dphys-swapfile` and `modprobe` with fakes, and `cmdline.txt` is a copy. No device is resized, no swap activated, nothing booted. On a real host, check by hand: `zramctl`, `swapon --show`, `journalctl --disk-usage`, `cat /proc/cmdline`.

## Pointers

Journal cap and disk full: `docs/runbooks/disque-plein-vm-lente.md`. Logs: `docs/adr/0011-journaux-victorialogs.md`. Unattended reboots: `ansible/roles/security/README.md`.
