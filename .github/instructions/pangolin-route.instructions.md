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

## 2. Create/extend `tofu/pangolin_config/website_<service>.tf`

Model it on `tofu/pangolin_config/website_sparky_fitness.tf` (simple,
single-target) or `tofu/pangolin_config/website_flip_planning.tf`
(multi-target, path-based sub-routing):

```hcl
resource "pangolin_resource" "<service>" {
  name        = "<Display Name>"
  subdomain   = "<subdomain>"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "<service>" {
  resource_id = pangolin_resource.<service>.id
  role_id     = pangolin_role.apps["<service-kebab>"].id
}

resource "pangolin_target" "<service>" {
  resource_id = pangolin_resource.<service>.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "<container_name>"
  port        = <port>
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "<container_name>"   # REQUIRED, see pitfall below
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_headers             = []
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "<service>" {
  resource_id = pangolin_resource.<service>.id
  title       = "Healthcheck ${pangolin_resource.<service>.name}"
}

output "<service>_access_token" {
  description = "<SERVICE> - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.<service>.id,
    token = pangolin_resource_access_token.<service>.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "<service>" {
  name            = "Healthcheck ${pangolin_resource.<service>.name}"
  url             = "https://${pangolin_resource.<service>.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.<service>.id),
    "P-Access-Token"    = pangolin_resource_access_token.<service>.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_<service>" {
  name = "Backup ${pangolin_resource.<service>.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_<service>_url" {
  description = "<SERVICE> - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_<service>.push_token}"
  sensitive   = true
}
```

The `uptime_backup_<service>_url` output is what `ansible/docker.yml` (or
`pangolin.yaml`/`pi.yml`) reads back to populate
`<service>_backup_healthcheck_url` — wiring that into the playbook is not
automatic, see `.github/instructions/borgmatic-backup.instructions.md`.

### Multi-target / sub-path routing

If a second component of the same app needs to live under a sub-path of the
same resource (e.g. pgAdmin under `/db`, see `website_flip_planning.tf`), add
a second `pangolin_target` block with its own `ip`/`port`/`hc_hostname`, plus:

```hcl
path            = "/db"
path_match_type = "prefix"
priority        = 2
```

on the second target, and on the catch-all target:

```hcl
path            = "/"
path_match_type = "prefix"
priority        = 1
```

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
  the healthcheck (fixed after the fact for `sparky_fitness`) — always set it
  explicitly to the container name.
- **`priority` is not "higher = matched first".** For path-based sub-routing,
  the catch-all `"/"` needs the *lowest* number and more specific paths need
  *higher* numbers — this was shipped backwards once for `flip_planning` and
  had to be fixed. Re-read `website_flip_planning.tf`'s inline comment before
  setting values if you're unsure.
