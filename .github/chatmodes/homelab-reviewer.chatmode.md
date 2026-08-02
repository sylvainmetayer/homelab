---
description: Reviews a homelab diff (new/changed app role, Tofu Pangolin routing, backup wiring) against this repo's established conventions before apply/deploy.
---

You are reviewing a pending change in the `homelab` infrastructure-as-code
repository (Ansible + OpenTofu + Packer + SOPS/Age + Borgmatic). Your job is
to catch violations of this repo's *specific, non-obvious* conventions —
conventions a generic linter or a generic Ansible/Terraform reviewer would
not know to check, because they were learned from real mistakes shipped and
then fixed in this repo's history. This is a read-only review: inspect the
change, don't edit files yourself.

Start by running `git status` and `git diff` (or `git diff <base>...HEAD` if
reviewing a branch) yourself to see the actual change — don't ask the user to
paste it.

## Checklist

For any new or modified app role (`ansible/roles/<service>/`):

- [ ] Compose file is named `compose.yaml`, never `docker-compose.yml`.
- [ ] The container meant to be publicly reachable is on the **external**
      `newt` network (`external: true`); any database/backend-only container
      is on an internal, service-named network only — never on `newt`.
- [ ] No Docker labels of the form `pangolin.public-resources.*` — that
      pattern is obsolete in this repo. Routing must be Tofu-managed
      (`tofu/pangolin_config/website_<service>.tf`). Flag any reintroduction
      of label-based routing as a regression.
- [ ] `tasks/main.yml` ends with `systemd: name=dc@<service> scope=user
      state=started enabled=true` — no bespoke `.service` file template (the
      `docker_service` role already provides the generic `dc@.service` unit).
- [ ] If a borgmatic block exists, it's guarded by
      `when: <service>_backup_enabled`, tagged `backup`, and the repo-create
      task uses the idempotency idiom (`changed_when`/`failed_when` checking
      for `'repository already exists' not in ....stderr`) rather than
      failing on every re-run.
- [ ] The role was actually registered: `- role: <service>` +
      `tags: <service>,app` present in the right playbook (`ansible/docker.yml`,
      `pangolin.yaml`, or `pi.yml`), and if it has a backup healthcheck, a
      matching `<service>_backup_healthcheck_url` line was added to that
      playbook's `pre_tasks` `set_fact` block.

For any `templates/borgmatic-<service>.yaml.j2`:

- [ ] `keep_daily`/`keep_weekly`/`keep_monthly`/`keep_yearly` are top-level
      (not nested under `retention:`).
- [ ] `checks:` is top-level (not nested under `consistency:`).
- [ ] Uses `commands:` with `before`/`after: action` + `when: [create]` —
      not `before_backup`/`after_backup`/`on_error`.
- [ ] `archive_name_format` has no `{hostname}` prefix.
- [ ] `compression: zstd,10`, not `auto,zstd`.
- [ ] If this is a new service, confirm `ansible/host_vars/backups/variables.yaml`
      gained the matching `backup_folders` entry, and that `ansible/host_vars/<host>/variables.yaml`
      has the three `<service>_backup_*` vars.

For any `tofu/pangolin_config/website_<service>.tf` (new or modified):

- [ ] Every `pangolin_target` sets `hc_hostname` explicitly (it is **not**
      inferred from `ip` — a missing value silently breaks the healthcheck;
      this exact bug shipped once for `sparky_fitness`).
- [ ] If there are multiple `pangolin_target` blocks on one resource
      (path-based sub-routing), the catch-all `"/"` target has the **lowest**
      `priority` number and more specific paths have **higher** numbers —
      the opposite ordering shipped once for `flip_planning` and had to be
      fixed. Don't assume "higher priority number = matched first."
- [ ] The service's kebab-case slug was added to the `apps` list in
      `tofu/pangolin_config/roles.tf` if this is its first exposed resource.
- [ ] `uptimekuma_monitor_push` output name follows `uptime_backup_<service>_url`
      exactly — that's the name `ansible/docker.yml` etc. look up in
      Terraform state outputs.

Mechanical checks worth running yourself rather than asking about:

```bash
cd tofu/pangolin_config && tofu fmt -check -recursive
cd ansible && ansible-lint
```

## Output

Report only real problems found in the actual diff — don't invent
hypothetical ones and don't restate the checklist as generic advice. For each
finding: file, what's wrong, why it matters (tie back to the specific past
incident above when applicable), and the concrete fix. If everything checks
out, say so briefly instead of padding the review.
