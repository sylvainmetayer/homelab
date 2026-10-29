# Secrets (SOPS + Age)

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

- Two SOPS files hold the secrets: `secrets.sops.yaml` at the repo root (OpenTofu/mise environment) and `ansible/secrets.sops.yaml` (what the playbooks load), both encrypted with Age (`.sops.yaml` lists the recipient age public keys: `perso`, `pro` and `secours` for both files, `github-actions` — the CI's `SOPS_AGE_KEY` — for `ansible/secrets.sops.yaml` only).
- `.sopsrc` (`ageKeyFile: /home/sylvain/.age.key`) is read only by the editor extension, not by sops: sops adds up `SOPS_AGE_KEY_FILE`, `SOPS_AGE_KEY`, `~/.config/sops/age/keys.txt` and `~/.ssh/id_ed25519` (see `docs/runbooks/test-cle-secours.md`).
- `mise.toml` auto-loads (and redacts) `secrets.sops.yaml` into task environments via `_.file`.
- In Ansible playbooks, secrets are loaded with:
  ```yaml
  community.sops.load_vars:
    file: "{{ playbook_dir }}/secrets.sops.yaml"
    expressions: evaluate-on-load
    return_method: vars-only
  ```
  `return_method: vars-only` needs ansible-core ≥ 2.21 (pinned in `uv.lock`, which the lint, test and deploy workflows install with `uv sync --locked`) and fails outright below it, instead of handing the secrets back as facts: those only reached the play through the deprecated fact injection, now off (`inject_facts_as_vars = False` in `ansible/ansible.cfg`, `ANSIBLE_INJECT_FACTS_AS_VARS=False` for Molecule; read facts as `ansible_facts[...]`). **Precedence**: the secrets land in the `include_vars` layer, so they **beat** role defaults, `group_vars`/`host_vars`, play `vars:`, the `vars:` of a `roles:` entry, a role's `vars/main.yml` and block/task `vars:`, and lose only to `set_fact`/registered vars, role and include params (the `vars:` of an `include_role`) and extra vars (the play and role-entry `vars:` cases checked on 2.21.5). A key of `ansible/secrets.sops.yaml` must therefore never bear the name of a variable that a playbook or a role sets (hence `host_user_password_hash`, not a generic `password`): prefix it per instance (`prod_planning_*`, `demo_planning_*`) and hand it over in the role entry's `vars:`. `.github/scripts/check_sops_shadowing.py` (Lint workflow; `python -I .github/scripts/check_sops_shadowing.py` from the repo root) fails on any such name.
- Every key of both SOPS files has an entry in `secrets-rotation.yaml` (kind, last rotation date, procedure), checked by `.github/scripts/check_secret_rotation.py` in the Lint workflow: adding or removing a SOPS key means adding or removing its entry; after a rotation, set `last_rotated` to the day and `estimated: false` in the same commit (`docs/runbooks/rotation-des-secrets.md`).
