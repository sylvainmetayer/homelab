# tofu/keycloak_demo_planning_kc

Realm Keycloak du banc `demo-planning-kc` (instance `demo_planning_kc` de
`ansible/flip.yml`, planning-equipes#72). **Temporaire** : à supprimer avec le
banc une fois la #72 mergée (skill `remove-app`). Le banc est **en pause**
aujourd'hui ([docs/runbooks/app-en-pause.md](../../docs/runbooks/app-en-pause.md)) :
ce module ne s'applique que s'il est repris.

## Ce que fait le module

- `modules/realm` : le realm décrit par `terraform/keycloak` du dépôt applicatif
  (planning-equipes), vendorisé tel quel depuis le commit
  `bb374eac0562365973530a1e8ec8f506fbc6c4d0` (inatteignable depuis une branche ou
  un tag, la source git ne s'initialisait plus). Il porte son propre bloc
  provider et se connecte avec le bootstrap admin du conteneur Keycloak : le mot
  de passe est lu dans `secrets/ansible.sops.yaml` (`secrets.tf`), aucune variable
  d'environnement à exporter.
- `main.tf` ne fait que l'instancier, avec un state distant
  (`homelab/keycloak_demo_planning_kc.tfstate` dans le bucket de `tofu/s3_state`).
- Les trois secrets de client (`app`, `provisioning`, `mcp`) sont tirés ici
  (`random_password`) : ils vivent donc dans le state. `flip.yml` les attend dans
  SOPS : `tofu output -raw …` pour les y reporter (phase 2).

## À savoir

- Le realm n'existe que si Keycloak tourne : appliquer après le démarrage de
  l'instance, jamais avant.
- Tests : `tests/keycloak_demo_planning_kc.tftest.hcl` (`mise run tofu-test`) ; le
  module est validé par `mise run lint`.
