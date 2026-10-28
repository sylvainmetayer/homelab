# 0011. Journaux centralisés : VictoriaLogs

- **Statut** : proposée (#931 serveur, #934 agents ; acceptée une fois déployée et mesurée)
- **Date** : 2026-10-28

## Contexte

Les journaux restent sur chaque hôte (journald, plafonné par `host_tuning`) :
un incident qui touche plusieurs hôtes veut dire une session SSH par hôte.
Beszel ne relaie que les 200 dernières lignes d'un conteneur, sans rien
garder ([0010](0010-supervision-beszel-uptime-kuma.md)).

## Décision

**VictoriaLogs seul**, en version légère : ni Grafana, ni métriques (Beszel).
Sur la VM docker, disque local, 30 jours et un plafond de 5 Gio, 320 Mio de
mémoire (plus 64 Mio pour vmauth, seul à le joindre, qui exige un compte :
lecture pour l'interface, écriture seule pour chaque agent). Interface vmui
sur `logs.sylvain.cloud`, derrière le SSO puis vmauth. Un agent Vector par
hôte (journald, conteneurs, journal d'accès de Traefik et CrowdSec sur
Pangolin), mémoire plafonnée. Aucune sauvegarde (journaux reproductibles).

## Alternatives écartées

- **Pile complète node_exporter + VictoriaMetrics/VictoriaLogs + Grafana** :
  écartée en octobre 2026 pour son poids sur la VM docker de 12 Gio (#79).
  Seule la partie journaux est reprise, à mesurer.
- **Rester sur journald par hôte** : suffisant d'après #79, voir Contexte.

## Conséquences

- Mesure après une semaine : `memory.peak` du stockage, de vmauth et des
  agents, et l'I/O wait de la VM (Beszel). Trop lourd : retrait
  (`docs/architecture.md`, « Les journaux », retour arrière).
- Journaux à secrets possibles : SSO puis vmauth, aucun chemin ouvert, ni
  chaîne de requête du journal d'accès de Traefik.

## Liens

#79 ; `docs/architecture.md` (« Les journaux (VictoriaLogs) »).
