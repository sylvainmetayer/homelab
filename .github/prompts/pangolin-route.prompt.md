---
mode: agent
description: Add or fix Pangolin resource/target/healthcheck/SSO routing in tofu/pangolin_config for a service.
---

Follow `.github/instructions/pangolin-route.instructions.md` in full.

Ask the user which service/container this is for (container name reachable
on the `newt` Docker network, port, subdomain) if not already given, then
create or extend `tofu/pangolin_config/website_<service>.tf` accordingly,
update `tofu/pangolin_config/roles.tf` if this is the service's first exposed
resource, run `tofu fmt -recursive && tofu validate && tofu plan` from
`tofu/pangolin_config`, and show the plan before applying.

Before finishing, explicitly confirm: every `pangolin_target` has
`hc_hostname` set, and — if there are multiple targets on one resource — the
catch-all `"/"` target has the lowest `priority` number.
