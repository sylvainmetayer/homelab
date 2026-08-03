---
mode: agent
description: Cleanly decommission a self-hosted app — stop its containers/service, delete its data and backups, then remove every trace from Ansible, host_vars, secrets and Tofu/Pangolin.
---

Follow `.github/instructions/remove-app.instructions.md` in full to remove an
app from this repo. Ask the user which service/slug, which host it runs on
(`docker` or `pi`), and whether the remote Borg repository on the Storage Box
should also be destroyed (default: no — keep the backup history) if not
already given, then:

1. Confirm the above with the user before touching anything — this is
   destructive.
2. Run the `decommission_app` role (`--tags decommission`) to stop/disable the
   systemd unit, tear down containers/volumes, and delete local data + the
   borgmatic config.
3. Delete `ansible/roles/<service>/` and deregister it from
   `ansible/docker.yml`/`ansible/pi.yml` (role entry + healthcheck `set_fact`
   line) — delete, don't comment out.
4. Remove its `host_vars` backup vars and its entry in `backup_folders`.
5. Remove any secrets for it from `secrets.sops.yaml` via `sops`.
6. Delete `tofu/pangolin_config/website_<service>.tf`, remove its slug from
   `roles.tf`'s `apps` list, then `tofu plan`/`tofu apply` and confirm
   `tofu state list | grep <service>` prints nothing.
7. Grep the whole repo for the service name and confirm nothing but
   incidental references remain — this is the exact step the `photoprism`
   removal skipped, leaving orphaned `host_vars`/`secrets.sops.yaml` entries
   that are still there today.

Before finishing, explicitly confirm: the `tofu plan` in step 6 showed a
*destroy* (not just a diff) for every `<service>`-named resource, and the
step 7 grep came back clean.
