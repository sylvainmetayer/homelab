# 0011. Journaux centralisés : VictoriaLogs

- **Statut** : proposée (aucune PR à ce jour)
- **Date** : à confirmer

## Contexte

Les journaux restent sur chaque hôte : `dc@` envoie ceux des conteneurs dans
journald, plafonné par `host_tuning`. Chercher un incident qui touche
plusieurs hôtes (Pangolin, Newt, l'appli) veut dire ouvrir une session SSH
par hôte. Beszel ne fait que relayer à la demande les 200 dernières lignes
d'un conteneur, sans rien garder ([0010](0010-supervision-beszel-uptime-kuma.md)).

## Décision

Centraliser les journaux dans **VictoriaLogs** ; les métriques restent à
Beszel. Hôte, collecteur, interface, rétention et sauvegarde : à confirmer
dans la PR qui l'introduira.

## Alternatives écartées

- **Pile complète node_exporter + VictoriaMetrics/VictoriaLogs + Grafana** :
  écartée en octobre 2026 pour son poids sur une VM de 12 Gio à disque
  rotatif (#79). Cette ADR n'en reprend que la partie journaux, à mesurer
  avant d'accepter.
- **Rester sur journald par hôte** : la situation actuelle, suffisante
  d'après #79 ; c'est ce que cette proposition remet en cause.

## Conséquences

- Sur la VM docker, une appli de plus qui écrit beaucoup sur un disque
  rotatif : mesurer `memory.peak` et les I/O avant d'en dépendre.
- Les journaux peuvent contenir des secrets : accès derrière le SSO, jamais
  de chemin ouvert.

## Liens

Issue #79 (« Hors périmètre / questions ouvertes », point 3) ; `TODO.md`
(piste Grafana + VictoriaLogs).
