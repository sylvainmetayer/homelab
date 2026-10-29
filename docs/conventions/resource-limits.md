# Resource limits doctrine

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Applies to every service of every compose (Docker VM first; the other hosts follow the same rules).

- **Resource limits doctrine** (the Docker VM has 3 cores / 12 GiB on the host's entry-level M.2 SATA SSD, a virtio-blk disk the guest reports as rotational — `ssd` emulation does not exist for virtio-blk; TRIM works through `discard = "on"` + `fstrim.timer`; aggregate CPU use is a few percent, so quotas only add latency):
  - Every service gets a `mem_limit` (hard cap). Size it at ~2× the measured peak (`memory.peak` in the container's cgroup), never below. A container pinned at its cap is not OOM-killed, it has its page cache evicted and thrashes the disk.
  - Databases (and anything measured at its cap) also get `mem_reservation` ≈ the peak: on cgroup v2 it becomes `memory.low` and protects their page cache.
  - **No `cpus:` on DBs, redis/valkey or interactive services.** A CFS quota below 1 core throttles any single-threaded burst even on an idle host.
  - Only batch-capable containers (OCR, document conversion, Celery workers) get `cpus: 2.00` + `cpu_shares: 512`: the cap always leaves one core to the rest, the weight makes them lose under contention and costs nothing when idle.
  - Check images' default worker counts (`GUNICORN_NUM_WORKERS`, `pm.max_children`…) against the cap: gramps defaulted to 8 gunicorn workers of 170 MiB under a 1 GiB cap and OOM-looped.
