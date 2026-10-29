# App lifecycle: second environment, pause, removal

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Adding an app: the `new-app` skill (`.claude/skills/new-app/SKILL.md`), which holds the former
« Adding a new app role » section.

## Running a second environment of an app

`flip_planning` is applied three times by `flip.yml`: production
(`flip-planning.sylvain.cloud`), the demo (`demo-planning.sylvain.dev`) and
the Keycloak demo (`demo-planning-kc.sylvain.dev`, `demo_planning_kc`). There is one role, not two — duplicating a role
per environment is what leaves the copy behind on the next change.

What makes a role instantiable is that everything two instances cannot share on
one Docker host derives from two variables, set in `defaults/` and overridden as
**role parameters** in the playbook:

- `<service>_service` (snake_case) — the compose project **directory** under
  `docker_base_path`, the systemd unit (`dc@<service>`) and the borgmatic config
  filename. Those are the same string by construction: `dc@.service` runs in
  `/opt/apps/%i`. Compose derives its project name from that directory, so
  volumes and internal networks are namespaced for free.
- `<service>_container_prefix` (kebab-case) — every `container_name` and the
  private docker network, hence what the Pangolin targets resolve on `newt`.

Four non-obvious rules, each of which silently crosses the two environments if
broken:

- **`vars:` on the `roles:` entry, not `host_vars` — and never a `set_fact`
  of the same name, nor a SOPS key of the same name.** `vars:` on a `roles:`
  entry wins over the role defaults and `host_vars`, but it **loses to a
  `set_fact`, to `include_vars` and to the keys loaded from
  `ansible/secrets.sops.yaml`** (`load_vars` registers them in the
  `include_vars` layer since ansible-core 2.21): checked, not assumed. Hence
  `prod_planning_*` / `demo_planning_*` in SOPS, each handed to its instance,
  and never a `flip_planning_*` key for a variable an instance overrides — the
  flip_planning Molecule converge fails on one. An override
  placed in `host_vars` would apply to *both* instances; a play-level
  `set_fact` of a name the role reads silently beats every instance's
  override. That is how the demo's backups pushed to the production Uptime
  Kuma monitor until `flip.yml` stopped `set_fact`ing
  `flip_planning_backup_healthcheck_url` itself (it now sets
  `prod_planning_backup_healthcheck_url` and hands it to the production
  instance).
- **One handler per instance, notified through a variable.** Handler names are
  matched literally and handlers run once, at the end of the play: a single
  shared handler notified by both applications restarts whichever unit happened
  to be in scope. Tasks do `notify: "Restart {{ <service>_service }}"` and
  `handlers/main.yml` carries one static handler per environment.
- **`allow_duplicates: true` in `meta/main.yml`.** Ansible skips a repeat
  application of a role whose parameters are identical. Differing parameters
  make it run anyway, so this is belt and braces — but the belt is at the call
  site, and a future environment that overrode nothing would be skipped without
  a word.
- **`set_fact` outlives the role application.** Anything a role `set_fact`s
  leaks into the next instance in the same play. In `flip_planning` that is
  `flip_planning_trusted_proxies`, and it is deliberately fine (same host, same
  newt bridge, same subnet) — check that it is fine before adding another.

On the Tofu side nothing is shared: a second `website_<instance>.tf` whose
entry is listed in `local.websites` (`websites.tf`: its resource, access token
and Uptime Kuma monitors come from there, and `rules.tf`'s `managed_resources`
is derived from it), a second slug in `roles.tf`'s `apps` and, for a standalone
rule, an entry in `declared_extra_rules`. Secrets are per-environment too (`demo_planning_*` in
`secrets.sops.yaml`), so a leaked demo password cannot open the real planning.

## Pausing an app

An app kept but unused (Paperless-ngx and Flip Planning's Keycloak demo
today) is paused, not removed: `docs/runbooks/app-en-pause.md`. Four switches
move together — the role's `<service>_enabled: false` in `host_vars` (unit stopped and disabled, restart
handler skipped, borgmatic config removed so the nightly dump cannot fail;
compose, data and borg repository kept), `enabled = false` in the app's
`local.websites` entry (resource disabled, healthcheck **and** backup monitors
paused, its targets' Pangolin probes off), the list of paused apps in `pangolin_config`'s invariants, and
`"paused": true` in `.github/restore-test/apps.json` (skipped by the scheduled
restore test; `tofu test` requires it exactly on the apps whose backup monitor
is paused). Renovate's « Paused apps » rules also disable the role's files and
its `path_bypass_images.json` entry (`enabled: false`, no update PR) while it is paused. `paperless_ngx` and `flip_planning` have the switch so far; each
Molecule `side_effect.yml` goes through both states. For a role applied more
than once (`flip_planning`), the switch is a role parameter of the instance's
`roles:` entry (`flip_planning_enabled: false` on `demo_planning_kc` in
`flip.yml`), never `host_vars`, and the restart is withheld at notify time
(`flip_planning_restart_handlers`), not by a handler `when`: handlers run with
the parameters of the role's last application in the play.

## Removing an app role

Use the **`remove-app`** project skill (`.claude/skills/remove-app/`) for the
full checklist — it's the reverse of `new-app` and touches the same files.
Summary: run the reusable `ansible/roles/decommission_app` role (registered
in `docker.yml`/`pi.yml`/`flip.yml`/`nas.yml` under `tags: [decommission, never]`, so it only ever
runs when invoked explicitly via `--tags decommission`) to stop/disable the
`dc@<service>` unit and delete containers/volumes/data/borgmatic config, then
delete the role directory, deregister it from the playbook (role entry +
healthcheck `set_fact` line), remove its `host_vars`/secrets
entries, delete its `tofu/pangolin_config/website_<service>.tf`, its line in
`websites.tf`'s `local.websites` and its slug from `roles.tf`'s `apps` list
(then `tofu apply`), and finally grep the whole
repo for the service name to confirm nothing was missed. That last step
matters: the `photoprism` removal (commit `7e848ed`) skipped it and left
orphaned `host_vars`/`secrets.sops.yaml` entries behind for months.
