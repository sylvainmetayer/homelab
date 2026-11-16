# neonova

Démo du futur site de Neonova sur `neonova.sylvain.dev`, derrière le SSO et un code PIN (`tofu/pangolin_config/website_neonova.tf`, clé SOPS `neonova_pin`).

La version de travail du site (brouillons compris) est construite par la CI du dépôt privé `Neonova-services/neonova-site` dans une image nginx, dont le package GHCR est privé. Pas de Pages Functions, donc les formulaires de devis et de rappel ne fonctionnent pas ici.

Aucune donnée, aucune sauvegarde. L'image suit le tag `main`, sans digest ni Renovate (règle `enabled: false`) : à la fin de chaque build, le workflow `image-demo.yml` de ce dépôt lance `deploy-docker-app` (`playbook=docker`, `tags=neonova`) avec le jeton `HOMELAB_DEPLOY_TOKEN`, et le rôle redémarre `dc@neonova`, qui retélécharge l'image. Sans ce jeton, ou s'il a expiré, la démo garde sa version et le build finit en échec.

Le même projet compose sert le site d'aide (`aide-neonova.sylvain.dev`, conteneur `neonova-aide`, tag `aide` du même package) : le dossier `aide/` du dépôt construit par Zensical. Même SSO, même PIN, même déploiement.

Un troisième conteneur sert l'aperçu de production (`apercu-neonova.sylvain.dev`, conteneur `neonova-apercu`, tag `apercu-prod` du même package) : le même site que la démo, brouillons exclus. Même SSO, même PIN, même déploiement.

## Identifiant GHCR

Le package `ghcr.io/neonova-services/neonova-site` est privé (compte `Neonova-services`, depuis le transfert du dépôt le 2026-11-16) : le rôle écrit `{{ neonova_base_path }}/.docker/config.json` (compte `neonova_ghcr_user`, jeton de la clé SOPS `neonova_ghcr_token`, un PAT classic `read:packages`) et un drop-in `~/.config/systemd/user/dc@neonova.service.d/registry.conf` qui pose `DOCKER_CONFIG` pour cette seule unité. Rien dans `~/.docker` : avec un jeton expiré ou révoqué là, ghcr.io refuserait tous les pulls de la VM, images publiques comprises.

- Sans la clé SOPS, le rôle échoue avant de toucher au compose : la démo garde son image.
- Jeton expiré ou accès au package retiré : le redémarrage de `dc@neonova` échoue au pull (`pull_policy: always`) et la démo s'arrête, rotation dans `docs/runbooks/rotation-des-secrets.md#jeton-ghcr-neonova`.
- Pull à la main sur l'hôte : `DOCKER_CONFIG=/opt/apps/neonova/.docker docker compose pull` dans le dossier du projet.
