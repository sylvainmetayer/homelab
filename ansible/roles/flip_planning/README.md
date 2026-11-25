# Role `flip_planning`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Applied twice by `flip.yml` (production `flip_planning`, and `demo_planning`, paused); the pattern that makes a role instantiable, and its four rules, are in `docs/conventions/app-lifecycle.md` (« Running a second environment of an app »). Pausing one instance: same file and `docs/runbooks/app-en-pause.md`.

- **Keycloak of production** (`flip_planning_keycloak_enabled`, under `/auth`, official image pinned in `templates/compose.yaml`): realm, bring-up order and memory budget in `tofu/keycloak_planning/README.md`. The application's OIDC switch (`flip_planning_oidc_enabled`) is separate: it closes the `admin` break-glass door.
