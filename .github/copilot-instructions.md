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
| Review a homelab diff before `tofu apply` / `ansible-playbook` | `.claude/agents/homelab-reviewer.md` | the **homelab-reviewer** chat mode |

The procedures live once, in `.claude/skills/*/SKILL.md` (the reviewer in
`.claude/agents/homelab-reviewer.md`). The `.github/prompts/*.prompt.md` slash
commands and the homelab-reviewer chat mode only point there: update the
skill or the agent, never a copy.
