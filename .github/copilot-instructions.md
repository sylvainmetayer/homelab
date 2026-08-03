# Copilot Instructions — Homelab Infrastructure

Read `AGENTS.md` at the repo root first — it's the canonical architecture and
commands reference for this repo (mise tasks, Ansible playbook mapping, Tofu
module layout, secrets handling, CI). Don't duplicate it from memory; if it
and this file ever disagree, `AGENTS.md` wins and this file should be fixed.

## Task-specific playbooks

This repo has learned several non-obvious, previously-bug-causing conventions
the hard way. For the tasks below, read the linked guidance in full and
follow it — don't improvise from generic Ansible/Terraform/Borgmatic
knowledge, it will be wrong in specific ways for this repo.

| Task | Read first | Or run |
|---|---|---|
| Add/deploy a new self-hosted app | `.github/instructions/new-app.instructions.md` | `/new-app` |
| Remove/decommission a self-hosted app | `.github/instructions/remove-app.instructions.md` | `/remove-app` |
| Add/fix Pangolin routing, healthchecks, or SSO (`tofu/pangolin_config/**`) | `.github/instructions/pangolin-route.instructions.md` | `/pangolin-route` |
| Add/fix a Borgmatic backup for a service | `.github/instructions/borgmatic-backup.instructions.md` | `/borgmatic-backup` |
| Review a homelab diff before `tofu apply` / `ansible-playbook` | switch to the **homelab-reviewer** chat mode | — |

The `.github/instructions/*.instructions.md` files are path-scoped and get
attached automatically when you touch matching files; the `.github/prompts/*.prompt.md`
files are the same content runnable on demand via the slash commands above.
Equivalent guidance also exists for Claude Code under `.claude/skills/` and
`.claude/agents/` — keep both in sync if you update one.

## Two mistakes already shipped once in this repo — don't repeat them

- Every `pangolin_target` in `tofu/pangolin_config/*.tf` needs `hc_hostname`
  set explicitly — it is **not** inferred from `ip`, and omitting it silently
  breaks the healthcheck (this happened for real, for `sparky_fitness`).
- For path-based multi-target routing on one Pangolin resource, the catch-all
  `"/"` target needs the **lowest** `priority` number and more specific paths
  need **higher** numbers — the opposite of what you'd guess (this shipped
  backwards once for `flip_planning` and had to be fixed).
