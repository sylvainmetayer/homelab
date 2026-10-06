---
applyTo: "tofu/pangolin_config/**"
description: How to add or fix Pangolin resource/target/healthcheck/SSO routing for a service, and the two ordering pitfalls already shipped once.
---

# Pangolin routing (Tofu-managed, not Docker labels)

**Important**: routing in this repo is managed entirely through the Pangolin
Terraform provider in `tofu/pangolin_config/`. There is no Docker-label-based
routing (`pangolin.public-resources.*`) anywhere in the current roles — Newt
only reads the Docker socket to validate the container is on the `newt`
network; the actual resource/target/healthcheck/SSO config lives in Tofu.

## Prerequisite

The container must join the **external** `newt` Docker network (declared
`external: true` in its `compose.yaml`, created by the `newt` Ansible role).
Pangolin/Newt reaches containers by name over that network — it does not
matter whether the container also sits on an internal network for a database.

## 1. Register the SSO role (first exposure of this service only)

Append the service's **kebab-case** slug to the `apps` list in
`tofu/pangolin_config/roles.tf`'s `locals` block. This controls who gets SSO
access to the resource created below.

## 2. Declare the app in `tofu/pangolin_config/website_<service>.tf`

The resource, its SSO role binding, its target(s), the healthcheck access
token, the inverted-keyword Uptime Kuma monitor and the backup push monitor
are **not** written per app: `tofu/pangolin_config/websites.tf` creates them
all with `for_each` over `local.websites`, with the pinned attributes
(`local.resource_pins`), the maintenance page (`local.maintenance`) and the
probe settings already set. An app only declares its entry and its outputs.
Model it on `website_searxng.tf` (simple, single-target) or
`website_flip_planning.tf` (multi-target, path-based sub-routing):

```hcl
# Resource, target and monitors: local.websites (websites.tf).
locals {
  <service>_website = {
    name      = "<Display Name>"
    subdomain = "<subdomain>"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "<service-kebab>" # the slug added to roles.tf in step 1
    backup    = true              # push monitor "Backup <Display Name>"

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "<container_name>" # also the probe's hc_hostname
      port    = <port>
      hc_path = "/health"          # optional, default "/"
    }
  }
}

output "<service>_access_token" {
  description = "<SERVICE> - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["<service>"]
  sensitive   = true
}

output "uptime_backup_<service>_url" {
  description = "<SERVICE> - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["<service>"]
  sensitive   = true
}
```

Then add `<service> = local.<service>_website` to `local.websites` in
`websites.tf` (the `every_public_resource_applies_its_rules` test fails if an
entry is left out). The key, snake_case, is what every generated address
carries: `pangolin_resource.website["<service>"]`,
`uptimekuma_monitor_push.backup["<service>"]`... `local.managed_resources`
(the country rules and the audits of `rules.tf`) is derived from
`local.websites`, nothing to register there.

`tests/invariants.tftest.hcl` pins the inventory on purpose, so that adding,
renaming or dropping an app is a visible decision and not a side effect. Add
the new app to:

- the resource name map of `every_public_resource_applies_its_rules` (key =>
  Pangolin name: a renamed name re-keys every country rule of the resource);
- the target key list of `every_probed_target_declares_scheme_mode_and_port`
  (one key per target, `<service>_<suffix>` for each sub_target);
- the healthcheck name map of `maintenance_page_and_inverted_keyword_monitors`
  (unless `healthcheck = false`);
- with `backup = true`, the backup name map of
  `monitors_are_filed_and_notify_by_email`, an `override_resource` giving
  `uptimekuma_monitor_push.backup["<service>"]` its own `push_token`, and the
  `uptime_backup_<service>_url` assertions of
  `outputs_read_by_ansible_point_at_their_own_push_monitor`;
- an `override_resource` giving `pangolin_resource.website["<service>"]` its
  own `id` (the country-rule run needs distinct ids);
- with path rules, the key list of `path_bypasses_open_exactly_the_reviewed_paths`.

The other fields of an entry, all optional, are documented at the top of
`websites.tf`: `sso` (default true), `enabled` (default true; false also
pauses the healthcheck monitor, while the backup monitor stays active since
the backup job keeps running), `healthcheck` (default true), `backup` (default
false), and on a target `hc_port` (default `port`), `path` and `priority`.
What is specific to one app stays in its file: path rules
(`local.<service>_*_paths`, turned into rules by `local.path_bypasses` in
`rules.tf`), home-IP rules, extra access tokens, a pincode.

The `uptime_backup_<service>_url` output is what `ansible/docker.yml` (or
`pangolin.yaml`/`pi.yml`) reads back to populate
`<service>_backup_healthcheck_url` — wiring that into the playbook is not
automatic, see the `borgmatic-backup` skill.

### Multi-target / sub-path routing

If a second component of the same app needs to live under a sub-path of the
same resource (e.g. pgAdmin under `/db`, see `website_flip_planning.tf`), give
the catch-all target `path = "/"` and `priority = 1`, and add the component
under `sub_targets`, keyed by a suffix (its address becomes
`pangolin_target.website["<service>_<suffix>"]`):

```hcl
    sub_targets = {
      pgadmin = {
        site_id  = pangolin_site.flip.id
        ip       = "<service>-pgadmin"
        port     = 80
        path     = "/db"
        priority = 2
        hc_path  = "/db/misc/ping"
      }
    }
```

A `path` always means a prefix match (`path_match_type = "prefix"`).

## 3. Validate and apply

```bash
cd tofu/pangolin_config
tofu fmt -recursive
tofu validate
tofu plan
tofu apply
```

## 4. Verify

```bash
curl -I https://<full_domain>
```

Check the resource's HTTP healthcheck goes green within `hc_interval` seconds
in Pangolin/Uptime Kuma.

## Pitfalls (both come from real bugs shipped in this repo)

- **`hc_hostname` is not inferred from `ip`.** Omitting it silently breaks
  the healthcheck (fixed after the fact for `sparky_fitness`). The
  generated targets of `websites.tf` set it to `ip`; a target written by
  hand (NAS, Proxmox) must set it explicitly to the container name.
- **`priority` is not "higher = matched first".** For path-based sub-routing,
  the catch-all `"/"` needs the *lowest* number and more specific paths need
  *higher* numbers — this was shipped backwards once for `flip_planning` and
  had to be fixed. Re-read `website_flip_planning.tf`'s inline comment before
  setting values if you're unsure.
