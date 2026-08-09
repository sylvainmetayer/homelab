---
mode: agent
description: Scaffold and wire up a new self-hosted application on the Proxmox docker host of this homelab.
---

Follow `.github/instructions/new-app.instructions.md` in full to add a new
app to this repo. Ask the user for the service name/slug, the container
image(s), the port to expose, and the subdomain if not already given, then:

1. Scaffold the Ansible role (`ansible/roles/<service>/`).
2. Register it in `ansible/docker.yml` (role entry + healthcheck URL fact).
3. Wire the Borgmatic backup (host_vars, `backup_folders`, borgmatic
   template) — see `.github/instructions/borgmatic-backup.instructions.md`.
4. Wire Pangolin routing/healthcheck/SSO in `tofu/pangolin_config/` — see
   `.github/instructions/pangolin-route.instructions.md`.
5. Run the validate/apply/deploy sequence from step 7 of the instructions.
6. Verify per step 8.

When creating `templates/compose.yaml`, use a concrete version tag matching the
latest available release (for example `:3.4.1`) rather than the floating
`:latest` tag, and avoid digest pinning (`@sha256:...`) unless the user
explicitly asks otherwise.

Call out explicitly, before finishing, whether `hc_hostname` was set on every
new `pangolin_target` and whether any multi-target `priority` values follow
the catch-all-gets-lowest-number rule — these are the two mistakes this repo
has actually shipped before.
