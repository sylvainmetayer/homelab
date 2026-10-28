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
- Plus tard, **k3s + Flux** comme terrain d'apprentissage, en migration
  partielle et réversible appli par appli (plan d'analyse du 2026-10-28 :
  cluster jetable, puis une VM k3s à côté de la VM docker ; Pangolin, le NAS,
  le Pi et flip restent dehors). Préalable : vérifier la RAM libre de l'hôte
  Proxmox et le vrai type du disque des VM (`ssd = false` dans Tofu).

## Alternatives écartées

- **Migrer la prod sur un k3s à un nœud** :
  - un seul nœud n'apporte presque aucune fiabilité : la VM tombe, tout
    tombe, comme aujourd'hui ;
  - environ 1,2 à 1,5 Gio de RAM de plus (estimation, à confirmer), sur une VM de 12 Gio ;
  - borgmatic resterait : la Storage Box n'est pas un stockage S3, cible des
    outils de sauvegarde de Kubernetes ([0001](0001-sauvegardes-borgmatic.md)).
- **Reprendre Talos** : déjà essayé et abandonné, faute de ressources
  (RAM, disque, matériel trop justes, d'après Sylvain le 2026-10-28) ; etcd,
  imposé par Talos même sur un nœud, aggrave ce point.

## Conséquences

- Le modèle `dc@` + Compose, ses tests Molecule et sa CI restent la seule
  façon de déployer la prod.

## Liens

Décision du 2026-10-28, hors PR (aucune trace écrite avant cet ADR).
