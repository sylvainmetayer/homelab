# Copilot Instructions — Homelab Infrastructure

Read `AGENTS.md` at the repo root first — it's the canonical index of this
repo: commands, the rules not to break, and a map to the detail (each role's
and Tofu module's `README.md`, `docs/conventions/*.md` for cross-cutting
topics: playbooks, secrets, tests, CI). Don't duplicate it from memory; if it
and this file ever disagree, `AGENTS.md` wins and this file should be fixed.

## Task-specific playbooks

This repo has learned several non-obvious, previously-bug-causing conventions
the hard way. For the tasks below, read the linked guidance in full and
follow it — don't improvise from generic Ansible/Terraform/Borgmatic
knowledge, it will be wrong in specific ways for this repo.

| Task | Read first | Or run |
|---|---|---|
| Add/deploy a new self-hosted app | `.claude/skills/new-app/SKILL.md` | `/new-app` |
| Remove/decommission a self-hosted app | `.claude/skills/remove-app/SKILL.md` | `/remove-app` |
| Add/fix Pangolin routing, healthchecks, or SSO (`tofu/pangolin_config/**`) | `.claude/skills/pangolin-route/SKILL.md` | `/pangolin-route` |
| Add/fix a Borgmatic backup for a service | `.claude/skills/borgmatic-backup/SKILL.md` | `/borgmatic-backup` |
| Review a homelab diff before `tofu apply` / `ansible-playbook` | switch to the **homelab-reviewer** chat mode | — |

The procedures live once, in `.claude/skills/*/SKILL.md`. The path-scoped
`.github/instructions/*.instructions.md` files and the `.github/prompts/*.prompt.md`
slash commands only point there: update the skill, never a copy.

## Two mistakes already shipped once in this repo — don't repeat them

- Every `pangolin_target` in `tofu/pangolin_config/*.tf` needs `hc_hostname`
  set explicitly — it is **not** inferred from `ip`, and omitting it silently
  breaks the healthcheck (this happened for real, for `sparky_fitness`).
- For path-based multi-target routing on one Pangolin resource, the catch-all
  `"/"` target needs the **lowest** `priority` number and more specific paths
  need **higher** numbers — the opposite of what you'd guess (this shipped
  backwards once for `flip_planning` and had to be fixed).
