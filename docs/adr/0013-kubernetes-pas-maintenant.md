# 0013. Kubernetes : pas pour la prod maintenant ; k3s + Flux pour apprendre, plus tard

- **Statut** : proposée
- **Date** : 2026-10-28

## Contexte

La prod tourne en Docker Compose sous systemd (`dc@<service>`), déployée par
Ansible. Un premier essai Kubernetes a existé : cluster Talos et Flux en mars
2025 (commits `b00823b3`, `9338821d`), effacé par la reprise du dépôt du
2026-01-09 (`0edd8ef6`, « start over »). Migrer la prod, ou apprendre ?

## Décision

- **Pas de Kubernetes pour la prod** tant qu'il n'y a qu'un nœud.
- Plus tard, **k3s + Flux** comme terrain d'apprentissage (forme et
  périmètre à confirmer).

## Alternatives écartées

- **Migrer la prod sur un k3s à un nœud** :
  - un seul nœud n'apporte presque aucune fiabilité : la VM tombe, tout
    tombe, comme aujourd'hui ;
  - environ 1,2 à 1,5 Gio de RAM de plus (estimation, à confirmer), sur une VM de 12 Gio ;
  - borgmatic resterait : la Storage Box n'est pas un stockage S3, cible des
    outils de sauvegarde de Kubernetes ([0001](0001-sauvegardes-borgmatic.md)).
- **Reprendre Talos** : déjà essayé et abandonné (raison non écrite, à
  confirmer).

## Conséquences

- Le modèle `dc@` + Compose, ses tests Molecule et sa CI restent la seule
  façon de déployer la prod.

## Liens

Décision du 2026-10-28, hors PR (aucune trace écrite avant cet ADR).
