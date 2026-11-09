# 0011. Journaux centralisés : VictoriaLogs

- **Statut** : acceptée le 2026-11-09 (déployée #931, #934 ; journaux des 6 hôtes reçus le 2026-11-03 ; mesure à une semaine relevée, voir Mesure)
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

## Mesure (2026-11-09)

Relevée sur tous les hôtes : `memory.peak`, `memory.events` (`max`,
`oom_kill`) et redémarrages du conteneur (`systemctl show` pour le LXC), plus
la moyenne de 2 h la plus haute des 7 derniers jours dans Beszel, seule
source qui remonte avant les recréations de conteneurs (chaque déploiement
remet `memory.peak` à zéro : les compteurs cgroup couvrent 3 à 5 jours selon
l'hôte, sauf victoria-logs et vmauth, recréés le soir même, d'où le relevé du
2026-11-04 sur docker).

| Conteneur | Hôte | Pic cgroup (Mio) | Moyenne 2 h max, 7 j (Mio) | Plafond | `max` / `oom_kill` / redémarrages |
|---|---|---|---|---|---|
| victoria-logs | docker | 227 (relevé du 04/11, 33 h) | 211 | 320 | 0 / 0 / 0 |
| vmauth | docker | 28 (04/11) | 23 | 64 | 0 / 0 / 0 |
| agent Vector | docker | 163 | 156 | 256 | 0 / 0 / 0 |
| agent Vector | pangolin | 133 | 190 | 256 | 0 / 0 / 0 |
| agent Vector | flip | 105 | 173 | 256 | 0 / 0 / 0 |
| agent Vector | pi | 132 | 149 | 256 | 0 / 0 / 0 |
| agent Vector | nas | 151 | 129 | 256 | 0 / 0 / 0 |
| agent Vector (unité) | newt-lxc | 72 (`MemoryPeak`) | n/a | 128 | n/a |
| proxy du socket | tous | 6 à 16 | 5 à 16 | 32 | 0 / 0 / 0 |

Les chiffres tiennent : aucun `max` ni `oom_kill`, aucun redémarrage, et les
plafonds de l'ADR sont gardés tels quels. Ils sont sous le double du pic
(victoria-logs 1,4×, agents de 1,3× à 2,4×) parce que le pic est surtout du
cache de fichiers récupérable, sans événement `max` en sept jours, et que la
VM docker manque de mémoire (swap plein au relevé) : ne rien monter sans
signal. À relire si un `max` apparaît sur un agent (pangolin et flip sont les
plus proches, avec 190 et 173 Mio de moyenne sur 2 h).

## Liens

#79 ; `docs/architecture.md` (« Les journaux (VictoriaLogs) »).
