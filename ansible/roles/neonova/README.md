# neonova

Démo du futur site de Neonova sur `neonova.sylvain.dev`, derrière le SSO et un code PIN (`tofu/pangolin_config/website_neonova.tf`, clé SOPS `neonova_pin`).

La version de travail du site (brouillons compris) est construite par la CI du dépôt privé `sylvainmetayer/neonova-services` dans une image nginx, dont le package GHCR est public : aucun login de registre sur l'hôte. Pas de Pages Functions, donc les formulaires de devis et de rappel ne fonctionnent pas ici.

Aucune donnée, aucune sauvegarde. L'image suit le tag `main`, sans digest ni Renovate (règle `enabled: false`) : à la fin de chaque build, le workflow `image-demo.yml` de ce dépôt lance `deploy-docker-app` (`playbook=docker`, `tags=neonova`) avec le jeton `HOMELAB_DEPLOY_TOKEN`, et le rôle redémarre `dc@neonova`, qui retélécharge l'image. Sans ce jeton, ou s'il a expiré, la démo garde sa version et le build finit en échec.
