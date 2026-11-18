# vitrine_asso

Démo du site d'une association, derrière le SSO et un code PIN (`tofu/pangolin_config/website_vitrine_asso.tf`, clé SOPS `vitrine_asso_pin`). Le nom de l'association reste hors de ce dépôt public : seul le sous-domaine de la ressource le porte, le nom de l'image est une clé SOPS.

Site statique (image nginx construite par la CI d'un dépôt privé, package GHCR privé), un seul conteneur, `vitrine-asso`, sur le port 8080. Aucune donnée, aucune sauvegarde.

L'image suit le tag `main`, sans digest ni Renovate (son nom n'est pas dans le dépôt) : à la fin de chaque build, le workflow du dépôt du site lance `deploy-docker-app` (`playbook=docker`, `tags=vitrine_asso`) avec son secret `HOMELAB_DEPLOY_TOKEN`, et le rôle redémarre `dc@vitrine_asso`, qui retélécharge l'image. Sans ce jeton, la démo garde sa version jusqu'au prochain passage du rôle.

## Clés SOPS

| Clé | Fichier | Rôle |
|---|---|---|
| `vitrine_asso_image` | `secrets/ansible.sops.yaml` | référence complète de l'image (`ghcr.io/<compte>/<paquet>:main`) |
| `vitrine_asso_pin` | `secrets/secrets.sops.yaml` | PIN de la ressource Pangolin, donné aux membres de l'association |
| `neonova_ghcr_token` | `secrets/ansible.sops.yaml` | jeton GHCR partagé avec le rôle `neonova` (PAT classic `read:packages` du compte `vitrine_asso_ghcr_user`) |

Sans `vitrine_asso_image` ou sans le jeton, le rôle échoue avant de toucher au compose : la démo garde son image.

## Identifiant GHCR

Comme pour `neonova` : le rôle écrit `{{ vitrine_asso_base_path }}/.docker/config.json` et un drop-in `~/.config/systemd/user/dc@vitrine_asso.service.d/registry.conf` qui pose `DOCKER_CONFIG` pour cette seule unité. Rien dans `~/.docker`. Jeton expiré : le redémarrage échoue au pull (`pull_policy: always`) et la démo s'arrête, rotation dans `docs/runbooks/rotation-des-secrets.md#jeton-ghcr-neonova` (le jeton sert aux deux rôles : relancer aussi `--tags vitrine_asso`).

Le compose n'est pas scanné par Trivy ni suivi par Renovate : la référence de l'image n'y est pas en clair.
