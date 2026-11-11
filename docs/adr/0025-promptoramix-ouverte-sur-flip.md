# 0025. Promptoramix : sur flip, ouverte de partout, gardée par sa seule signature HMAC

- **Statut** : acceptée
- **Date** : 2026-10-16

## Contexte

Promptoramix, l'IA Rust du tournoi Linkx de Marmelab, est appelée par des fonctions
edge Supabase : pas de navigateur, pas de plage de sortie stable. Elle ne peut
donc tenir ni derrière le SSO, ni derrière le FR/DE de [0002](0002-pangolin-seule-entree-publique.md).

## Décision

- **Exception à 0002** : sans SSO, `ACCEPT /coup` et `/health` en priorité 2, avant
  les règles de pays. La signature HMAC (`LINKX_SECRET`) de chaque POST, vérifiée par
  l'appli, est la seule garde (`/health` répond sans, et ne révèle rien). Tout autre
  chemin : `DROP /*` en priorité 3 (`promptoramix_drop`). Pangolin ne filtre pas la
  méthode : `GET /coup` passe, l'appli répond 405. (Décision d'origine du 16/10 :
  `ACCEPT /*`, restreinte le 07/11/2026 aux routes réellement appelées.)
- **Sur flip**, un conteneur à 256 Mio, sans base ; choisie plutôt que la VM
  docker parce qu'elle avait de la place, la VM docker étant déjà chargée
  (confirmé par Sylvain le 2026-11-11).
- **Automerge de chaque digest de `main`**, sauf le jeudi de 0 h à 12 h : un
  redémarrage pendant la vague du tournoi ferait perdre les parties en cours.

## Alternatives écartées

- **Filtre FR/DE** : la plupart des coups tomberaient sur le `DROP` final.
- **SSO** : pas de navigateur pour passer le mur ; jeton ou en-tête Pangolin (Papra, Grocy) non étudiés, à confirmer.

## Conséquences

- Une faille du contrôle HMAC serait exposée au monde entier ; devant, seuls le DROP
  d'antislash et CrowdSec restent ([0003](0003-crowdsec-sur-pangolin.md)), qui peut aussi
  bannir une IP partagée de Supabase, sans alerte ([runbook](../runbooks/crowdsec.md)).
- Chaque push sur `main` de l'appli part en production sur flip, à côté du planning.
- Journal des coups sur un volume (`./journal`, #771), non sauvegardé : fichier
  d'appoint. L'appli n'est donc pas tout à fait « sans état ».
- Retrait à la fin du tournoi (confirmé par Sylvain le 2026-11-11) ; la date
  n'est pas connue ici.

## Liens

PR #738, #771 ; `tofu/pangolin_config/website_promptoramix.tf`, `ansible/roles/promptoramix/`.
