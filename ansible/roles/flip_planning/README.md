# Role `flip_planning`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Applied four times by `flip.yml` (the fourth, `exemple_planning`, is the public showcase reset every night: `flip_planning_reset_dump` in `defaults/main.yml`, `files/exemple/README.md`); the pattern that makes a role instantiable, and its four rules, are in `docs/conventions/app-lifecycle.md` (« Running a second environment of an app »). Pausing one instance: same file and `docs/runbooks/app-en-pause.md`.

- **Avant de rétablir `exemple_planning`** (public sans SSO, en pause) : le placer sur `newt-public` et non `newt` (`newt_public_network_enabled`, README du rôle `newt`). Le compose et la lecture du sous-réseau des proxys de confiance (`flip_planning_newt_network`, lue une fois pour toutes les instances) sont encore ceux de `newt`.
