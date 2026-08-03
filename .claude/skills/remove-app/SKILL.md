---
name: remove-app
description: Cleanly decommission an app previously deployed with the new-app skill — stop its containers/service, delete its data and backups, then remove every trace from docker.yml/pi.yml, host_vars, backups list, secrets and Tofu/Pangolin. Use when the user asks to remove, decommission, uninstall or tear down a self-hosted app.
---

# Remove a deployed app cleanly

This is the reverse of the **new-app** skill: same ~7 touchpoints, but deleting
instead of adding. **The `photoprism` removal (commit `7e848ed`) got this
wrong** — it deleted the role directory but left `photoprism` behind in
`host_vars/backups/variables.yaml`, `host_vars/pi/variables.yaml`, and
`secrets.sops.yaml` (still there today). Don't repeat that: grep the whole
repo for the service name at the end (step 6) before calling this done.

Pick up the service's slug the same way `new-app` assigns it: `snake_case`
Ansible name, `kebab-case` Pangolin slug.

## 0. Confirm intent with the user before touching anything

This is destructive and not easily reversible (container data + local backup
config are deleted; the remote Borg repo only if you explicitly ask for it).
Before running anything, confirm with the user:
- Which service, exactly (there's no undo for a typo'd `decommission_app_service`).
- Whether they also want the **remote** Borg repository on the Storage Box
  destroyed, or just stopped/unbacked-up going forward (default: keep it —
  `decommission_app_destroy_remote_backup` defaults to `false`).

## 1. Stop containers and delete local data — `decommission_app` role

A reusable role already exists at `ansible/roles/decommission_app/` (added
alongside this skill, registered in both `docker.yml` and `pi.yml` tagged
`[decommission, never]` — the `never` tag means it only runs when you pass
`--tags decommission` explicitly, so it can never fire during a normal
`docker.yml`/`pi.yml` apply). It:

1. Asserts `decommission_app_confirm: true` plus service/base_path are set —
   refuses to run otherwise.
2. Stops + disables the `dc@<service>` systemd unit.
3. Runs `docker compose down --volumes --remove-orphans` in the app's base
   path (removes containers, networks, and named volumes).
4. Optionally (`decommission_app_destroy_remote_backup: true`) runs
   `borgmatic repo-delete --force` against the Storage Box repo — irreversible.
5. Removes the borgmatic config (`{{ borgmatic_config_dir }}/<service>.yaml`).
6. Removes the app's data directory (`<service>_base_path`).

Run it, targeting whichever host the app actually lives on (`docker` or `pi`):

```bash
cd ansible
ansible-playbook -i inventory/hosts docker.yml --tags decommission --limit docker \
  -e decommission_app_confirm=true \
  -e decommission_app_service=<service> \
  -e decommission_app_base_path="{{ docker_base_path }}/<service>" \
  -e decommission_app_destroy_remote_backup=false
```

If this role doesn't exist yet in a given checkout (e.g. this skill was
copied to another repo), scaffold it from the description above before
proceeding — don't hand-roll a one-off teardown per app; the whole point is
one generic role reused for every future removal.

## 2. Delete the Ansible role directory

```bash
rm -rf ansible/roles/<service>
```

## 3. Deregister from the playbook(s)

In `ansible/docker.yml` (and/or `ansible/pi.yml`, whichever the app was on):
- Remove the `- role: <service>` / `tags: <service>,app` entry from `roles:`.
- Remove its `<service>_backup_healthcheck_url: ...` line from `pre_tasks` →
  `Load healthcheck URLs from Terraform state outputs`.

(This is exactly the mirror image of `new-app` step 2 — and exactly the step
the `photoprism` removal got half-right: it commented out the role in
`pi.yml` instead of deleting the block, and never touched the `set_fact`.
Delete, don't comment out.)

## 4. Remove host_vars

- Delete the `<service>_backup_enabled` / `_backup_borgmatic_target` /
  `_backup_encryption_passphrase` block from
  `ansible/host_vars/<host>/variables.yaml`.
- Remove `"<service>"` from `backup_folders` in
  `ansible/host_vars/backups/variables.yaml`. This only stops the folder from
  being (re)created — it does **not** delete anything already on the Storage
  Box (that's `decommission_app_destroy_remote_backup` in step 1, or manual
  cleanup on the box if you skipped it).

## 5. Remove secrets

If the service had entries in `secrets.sops.yaml` (DB password, admin
password, API keys, its own `_backup_healthcheck_url`), remove them via
`sops secrets.sops.yaml` — never hand-edit the encrypted blob.

## 6. Remove Pangolin/Tofu routing

Everything the `pangolin-route` skill creates for a service (`pangolin_resource`,
`pangolin_resource_role`, `pangolin_target`, `pangolin_resource_access_token`,
`uptimekuma_monitor_http`, `uptimekuma_monitor_push`, plus the two Terraform
outputs) lives in one file, so removal is two edits + an apply:

- Delete `tofu/pangolin_config/website_<service>.tf` in full.
- Remove the service's kebab-case slug from the `apps` list in
  `tofu/pangolin_config/roles.tf`'s `locals` block (this destroys its
  `pangolin_role`, which also revokes any SSO/user access to it — nothing
  else to clean up there, Pangolin doesn't track per-user role grants in Tofu).
- Apply so Tofu actually destroys what's provisioned (deleting the `.tf` file
  alone only drops it from the *next* plan, it doesn't tear down existing
  resources):

```bash
cd tofu/pangolin_config
tofu fmt -recursive
tofu plan    # must show a *destroy* for every <service>-named resource, not just a diff
tofu apply
tofu state list | grep <service>   # should print nothing once applied
```

Two things you don't need to touch, for context: `rules.tf`'s country-allow
rules are generated with `for_each` over `data.pangolin_resources.all.resources`,
so they disappear automatically once the resource is destroyed; and
`tofu/dns/pangolin.tf` is a single wildcard (`subdomain = "*"`) record, not
per-app, so there's no DNS record to remove either.

## 7. Repo-wide leftover check (don't skip — this is what went wrong last time)

```bash
grep -rln "<service>" --include="*.yml" --include="*.yaml" --include="*.tf" . \
  | grep -v -E "^\./(tofu/pangolin_config/\.terraform|ansible/collections|ansible/\.ansible|ansible/galaxy_roles)"
```

Anything left should only be incidental (e.g. a changelog, an unrelated
comment). If `host_vars`, `secrets.sops.yaml`, `backup_folders`, or a
commented-out (not deleted) playbook role entry show up, go back and finish
steps 3–5.

## 8. Verify

```bash
systemctl --user status dc@<service>          # should be "not found" / inactive
docker ps -a | grep <service>                   # should be empty
curl -I https://<old_subdomain>.sylvain.cloud   # should no longer resolve/route
ansible-lint
```

Also check Uptime Kuma / Pangolin for the removed HTTP and backup-push
monitors — `tofu apply` in step 6 should have deleted them; if they're still
listed, the `tofu plan` in step 6 didn't actually target them (check the
resource names matched `<service>` exactly).
