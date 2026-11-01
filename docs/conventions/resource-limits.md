# Resource limits doctrine

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Applies to every service of every compose (Docker VM first; the other hosts follow the same rules).

- **Resource limits doctrine** (the Docker VM has 3 cores / 12 GiB on the host's entry-level M.2 SATA SSD, a virtio-blk disk the guest reports as rotational — `ssd` emulation does not exist for virtio-blk; TRIM works through `discard = "on"` + `fstrim.timer`; aggregate CPU use is a few percent, so quotas only add latency):
  - Every service gets a `mem_limit` (hard cap). Size it at ~2× the measured peak (`memory.peak` in the container's cgroup), never below. A container pinned at its cap is not OOM-killed, it has its page cache evicted and thrashes the disk.
  - Databases (and anything measured at its cap) also get `mem_reservation` ≈ the peak: on cgroup v2 it becomes `memory.low` and protects their page cache.
  - **No `cpus:` on DBs, redis/valkey or interactive services.** A CFS quota below 1 core throttles any single-threaded burst even on an idle host.
  - Only batch-capable containers (OCR, document conversion, Celery workers) get `cpus: 2.00` + `cpu_shares: 512`: the cap always leaves one core to the rest, the weight makes them lose under contention and costs nothing when idle.
  - Check images' default worker counts (`GUNICORN_NUM_WORKERS`, `pm.max_children`…) against the cap: gramps defaulted to 8 gunicorn workers of 170 MiB under a 1 GiB cap and OOM-looped.

## Disk I/O (Docker VM)

The disk, not CPU or RAM, is the bottleneck. Measure it with cgroup counters, never by reading the journal over weeks:

- Per container: `io.stat` of `/sys/fs/cgroup/system.slice/docker-<id>.scope` (device `254:0`, `vda`; `253:0` is zram), read twice ~10 min apart for a rate, outside borgmatic's 00:30-03:00 window. `/proc/pressure/io` for the stall, `/proc/fs/jbd2/vda1-8/info` for the ext4 journal (a commit « requested » is an `fsync`).
- Measured 2026-11-01 23:55-00:06 (PR #<n>): reads ~10 MB/s, 93 % from `dawarich-db` (seq scans of `points`, 4.8 GB, against a 1.1 GiB page cache); writes ~1.1 MB/s, first FreshRSS (`rss`: SQLite in rollback-journal mode, `synchronous=FULL`, 846 feeds, ~100 KB/s on average over 68 h), then journald (~50 KB/s for ~250 B/s of text: under `dc@` every container line is also copied into the user journal), dockerd's json-file logs (~35 KB/s for ~400 B/s of text), dawarich's Redis snapshots. jbd2: ~3.6 fsync-driven commits/s.
- Small appends cost a 4 KiB page plus an ext4 journal commit each: a log line or a healthcheck request is cheap in bytes, not in I/Os. Silence per-request INFO logs of healthchecks, space out snapshots (`redis --save`).
