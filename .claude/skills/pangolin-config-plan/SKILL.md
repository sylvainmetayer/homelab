---
name: pangolin-config-plan
description: Prepare a worktree, run and read a `tofu plan` of tofu/pangolin_config (Pangolin resources, rules, roles, Uptime Kuma monitors), then apply it only within the rules Sylvain delegated. Use after a merge touching tofu/pangolin_config, after a provider bump, to check for drift, or whenever asked to plan or apply that module.
---

# Plan (and maybe apply) tofu/pangolin_config

This module drives the live Pangolin instance and Uptime Kuma: an apply changes
who can reach which app, right away. The plan is cheap and read-only; the
apply is not. Writing the change itself is the `pangolin-route` skill; this
one is everything around `tofu plan` / `tofu apply`.

## 0. Who applies

`AGENTS.md`: Sylvain runs the applies. Without a delegation **in this
session**, stop at the plan and hand over the apply command. A delegation so
far has been narrow: apply alone only an empty plan, or one holding nothing
but `uptimekuma_*` **creations** and the `terraform_data.access_inventory`
counter. Anything else (an update, a destroy, a replace, a rule, a role, a
binding, SSO, the identity provider): show Sylvain the planned changes, wait.
Never `tofu destroy`, never `force-unlock` a state lock someone else holds.

## 1. Worktree on what is merged

Apply only what is on `origin/main`: the state (S3, shared) would otherwise
hold resources main does not declare, and the next plan from main would
destroy them. A PR branch is planned to read it, never applied.

```bash
git fetch origin main                          # alone
git worktree add --detach .claude/worktrees/plan-pc origin/main
cd .claude/worktrees/plan-pc
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git submodule update --init secrets            # alone
mise trust .                                   # outside the sandbox if any
bash .github/scripts/fetch_pangolin_provider.sh   # = mise run provider-fork, which fails in a sandbox
mise exec -- tofu -chdir=tofu/pangolin_config init -input=false -no-color
```

Use `origin/main`, never `FETCH_HEAD`: `FETCH_HEAD` belongs to the worktree
that fetched, so one read from another directory can be hours old. A stale
checkout plans the **destruction** of whatever was merged since (seen on
2026-11-05: the three S.M.A.R.T. monitors, « not in configuration »).

`mise exec` loads the SOPS-backed `TF_VAR_*`. In a Claude sandbox, every
`tofu` / `mise exec -- tofu` / `git fetch` / `git submodule` command runs
**alone**: chained, piped or redirected, it stays sandboxed, gets no SOPS key
and fails on credentials.

## 2. Plan and read it

```bash
P=$SCRATCH/pc.tfplan          # a session scratch dir, never the repo
mise exec -- tofu -chdir=tofu/pangolin_config plan -input=false -no-color -concise -compact-warnings -out=$P
```

The text plan masks sensitive values (`(sensitive value)`): read it there.
Never `tofu show -json` of the plan nor a raw `tofu output` into the session:
both hold push and access tokens in clear (a classifier refuses the first,
rightly). Classify from the `# <address> will be ...` lines and the `Plan:`
line: `uptimekuma_* will be created` and `terraform_data.access_inventory will
be updated in-place` are the delegable ones; anything else is Sylvain's.

Read the warnings too:

| Message | Meaning | Blocks? |
|---|---|---|
| `check "target_health"` | a target's probe fails now | no: Uptime Kuma pages; say which |
| `check "travel_countries_stale"` / `"inventory_exceptions_stale"` | dead entry to remove | no: report it |
| precondition « resource list is truncated » / « Could not read the Pangolin » | the audit had no complete data | yes: retry; if it persists, an API change |
| precondition « Enabled Pangolin resources with no country rules » | a resource made in the UI | yes: Sylvain declares, deletes or disables it |
| `Error acquiring the state lock` | someone else is planning/applying | yes: wait, ask; never force-unlock |

## 3. Before trusting the plan

- **A destroy « because ... is not in configuration »**: first suspect your
  checkout (section 1), then a file removed on purpose. Never apply it on a
  guess.
- **« No changes » is not proof for undeclared optional+computed attributes**:
  the plan cannot see their live value (AGENTS.md hard rule, two outages). A
  new attribute in the diff you are checking must be declared.
- **A recreated PIN, password or header auth with nothing changed** on the
  server is a read problem, not drift: provider ≤ `1.7.0-sylvain.2` read only
  the first 20 items of the org lists. Check the live object through the API
  (`pageSize=1000`) before applying anything that recreates auth.
- **`-target` pulls in dependencies**: a targeted apply also applies whatever
  its target depends on (Nextcloud's SSO came back that way on 2026-11-04).
  Run `plan -target=...` and read *its* summary; `-exclude=<addr>` exists to
  leave one change out.
- A `pangolin_site_resource` update keeps its bindings on the fork; on an
  upstream provider it may not (`tofu/pangolin_config/README.md`).

## 4. Apply the plan you read

```bash
mise exec -- tofu -chdir=tofu/pangolin_config apply -input=false -no-color -concise -compact-warnings $P
mise exec -- tofu -chdir=tofu/pangolin_config plan -input=false -no-color -detailed-exitcode
```

Apply the saved plan file, never a fresh `apply -auto-approve`: that one
would re-plan and could carry what you did not read. The follow-up plan must
exit `0` (empty); `2` means something did not converge, report it.

## 5. After

- A new push monitor's URL is a module output that Ansible reads at deploy
  time (`ansible/tasks/pangolin_config_outputs.yml`): the monitor stays red
  until the role that pushes is deployed (merge to main, or the host playbook
  by hand for `nas.yml`, `pve.yml`, `lxc.yml`).
- A new or changed route: `curl -I https://<full_domain>`, target healthy in
  Pangolin within 60 s, Uptime Kuma green within 5 min.
- Remove the worktree when done: `git worktree remove .claude/worktrees/plan-pc`.
- Say what was applied, the follow-up plan's exit code, and what is still red
  and why.
