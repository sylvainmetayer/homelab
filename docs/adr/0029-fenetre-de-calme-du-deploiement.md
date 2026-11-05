# 0029. Fenêtre de calme : pas de déploiement automatique de 19:00 à 08:00

- **Statut** : acceptée (précise [0024](0024-deploiement-au-merge.md), qui reste valable)
- **Date** : 2026-11-05

## Contexte

Un merge déploie aussitôt ([0024](0024-deploiement-au-merge.md)), même le soir
pendant un film ou la nuit : un redémarrage d'appli tombe au pire moment, sans
personne pour réagir à un échec. Le run suivant rattrape déjà les runs annulés
ou rouges : il déploie tout depuis le dernier run **réussi**.

## Décision

- **19:00-08:00, heure de Paris, tous les jours**, week-end compris : un run
  automatique (push ou `schedule`) s'annule au démarrage (job `window`,
  `deploy_window.py`). L'heure est jugée au démarrage du run, pas au push.
- **Annulé, pas sauté** : un `deploy` sauté laisserait le run vert, donc
  « dernier succès », et ses commits seraient perdus. Un run annulé n'est jamais
  une base : le premier run de la fenêtre déploie tout depuis le dernier succès.
- **Un `schedule` rouvre** : `0 6,7,9 * * *` UTC. 08:00 Paris = 06:00 UTC l'été,
  07:00 UTC l'hiver ; l'autre tombe à 09:00 et ne trouve rien ; 09:00 UTC est
  un filet. Son rattrapage part du dernier succès (push ou schedule) jusqu'à
  `main`, ou ne fait rien.
- **`workflow_dispatch` toujours immédiat** : l'exception des correctifs urgents.

## Alternatives écartées

- **`if:` sur le job (sauté)** : run vert, commits perdus.
- **Échouer le run** : rattrape aussi, mais une croix rouge chaque soir, et le
  digest Renovate (runs en échec) perd son sens.
- **Heure UTC fixe** : fausse d'une heure la moitié de l'année.
- **Attendre dans le run jusqu'à 08:00** : tient la file de `concurrency`
  (un seul run en attente par groupe) et un runner dix heures.

## Conséquences

- Un merge du soir, Renovate compris, se déploie à 08:00. Renovate ne souffre de rien.
- Un `schedule` n'est pas garanti à la minute, peut être retardé ou sauté, et
  est coupé après 60 jours sans activité. Le filet et le prochain push limitent
  le retard : rien n'est perdu, seulement différé.
- Un run démarré à 18:59 va au bout. Chaque matin, trois runs de rattrapage,
  presque tous sans rien à déployer.

## Liens

`.github/workflows/deploy-docker-app.yaml`, `.github/scripts/deploy_window.py`
et son test ; [ci.md](../conventions/ci.md), [deploiement-ci-casse.md](../runbooks/deploiement-ci-casse.md).
