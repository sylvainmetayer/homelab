# neonova

Démo du futur site de Neonova sur `neonova.sylvain.dev`, derrière le SSO et un code PIN (`tofu/pangolin_config/website_neonova.tf`, clé SOPS `neonova_pin`).

La version de travail du site (brouillons compris) est construite par la CI du dépôt privé `sylvainmetayer/neonova-services` dans une image nginx, dont le package GHCR est public : aucun login de registre sur l'hôte. Pas de Pages Functions, donc les formulaires de devis et de rappel ne fonctionnent pas ici.

Aucune donnée, aucune sauvegarde. Une nouvelle version du site arrive par le digest que Renovate met à jour.
