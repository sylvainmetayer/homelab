# Role `update_notify`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Part of `pve.yml` (row in `docs/conventions/ansible.md`), mode `apt`.

`update_notify` (tag `update_notify`, apt only: every Monday `update-notify.timer` runs `apt-get update` and an `apt-get -s dist-upgrade` simulation, never installs anything, and publishes the pending list to ntfy topic `scripts`, security first, then Proxmox/kernel packages, plus a pending reboot when a newer kernel is installed; priority high when a Debian-Security update waits; pushes to the `Mises à jour Proxmox` monitor, `uptime_cron_pve_updates_url`, so `pve.yml` now reads the `pangolin_config` state too; procedure: `docs/runbooks/mises-a-jour-proxmox-ugos.md`)
