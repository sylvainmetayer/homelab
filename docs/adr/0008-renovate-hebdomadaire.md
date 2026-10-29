# 0008. Renovate : PR hebdomadaires groupées, images à état manuelles, automerge ciblé

- **Statut** : acceptée
- **Date** : 2026-10-06 (majeures à état), 2026-10-27 (groupe hebdo), 2026-10-28 (automerge), 2026-10-29 (liste élargie, apps en pause ; cadence plus calme)

## Contexte

Toutes les images sont épinglées par digest : Renovate ouvre beaucoup de
PR, chacune relance la CI (une heure de matrice avant #883), et un merge
sur `main` déploie. Une majeure de base change son format sur disque,
parfois sans retour arrière.

## Décision

- **Digests et correctifs** : une PR le lundi avant 9 h ; mineures et majeures à part.
- **Images à état** (Postgres, MariaDB, Redis/Valkey, Meilisearch) : une
  majeure attend une case cochée sur le Dependency Dashboard ; MariaDB reste
  sur la LTS 12.3, Redis `-bookworm` plafonné à 8.2.
- **Automerge ciblé**, CI verte : **liste blanche** d'images sans état
  (gotenberg, tika, stirling-pdf, homepage, nginx, karakeep-chrome, rclone,
  debian de l'image Molecule ; hors `flip_planning`), correctifs
  des GitHub Actions, nos images (planning-equipes hors majeures, promptoramix) ; jamais si `path_bypass_images.json` change.
- **Apps en pause** : aucune PR (`enabled: false` sur les fichiers du rôle,
  Paperless-ngx aujourd'hui), la règle part à la reprise.
- **Cadence plus calme** (2026-10-29, 152 PR Renovate mergées en 30 jours) :
  version tierce proposée 3 jours après sa publication (au lieu d'un) ;
  mineures groupées le lundi dans leur propre PR, à la main ; **toute**
  majeure attend sa case sur le Dependency Dashboard ; rebase seulement en
  conflit (le ruleset n'exige pas de branche à jour). Nos images restent
  hors délai, fenêtre et case. Le correctif de sécurité urgent passe par
  l'alerte CRITICAL de Trivy du lundi, bump à la main.

## Alternatives écartées

- **Une PR par mise à jour** : une CI par PR, tout le monde attend.
- **Automerge en liste noire** : une appli qui migre ses données au
  démarrage partirait sans relecture.
- **Automerge des digests d'actions** : un nouveau digest sous le même tag,
  c'est un tag déplacé (attaque tj-actions, mars 2025).

## Conséquences

- Molecule ne tire aucune image : une image automergée qui démarre puis
  plante laisse la CI verte, seul Uptime Kuma le voit. Retour arrière :
  revert **et** retrait de la liste blanche.

## Liens

PR #700, #883, #911, #923 ; `renovate.json` (une description par règle) ;
[runbooks/deploiement-ci-casse.md](../runbooks/deploiement-ci-casse.md).
