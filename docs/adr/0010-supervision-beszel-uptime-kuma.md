# 0010. Supervision : Beszel pour les hôtes, Uptime Kuma (PikaPods) pour les services

- **Statut** : acceptée
- **Date** : 2026-10-26 (Beszel) ; Uptime Kuma : date à confirmer

## Contexte

Uptime Kuma voyait la disponibilité HTTP, les sauvegardes et les connexions
SSH, aucune métrique système ; or les incidents passés étaient surtout un
disque plein ou une VM docker lente (disque rotatif, 12 Gio).

## Décision

- **Beszel** : un hub (`dc@beszel`, VM docker, `monitoring.sylvain.cloud`
  derrière le SSO) et un agent par hôte. L'agent appelle le hub, aucun port
  n'écoute ; Pangolin et flip passent par un PASS sur
  `/api/beszel/agent-connect` avec un jeton Pangolin par agent. Socket
  Docker derrière un `socket-proxy` en GET seulement.
- **Uptime Kuma chez PikaPods**, hors du homelab, déclaré par
  `tofu/pangolin_config` : il voit tomber la VM docker, donc le hub.
- Journaux : journald par hôte ([0011](0011-journaux-victorialogs.md)).

## Alternatives écartées

- **node_exporter + VictoriaMetrics/VictoriaLogs + Grafana** (piste du
  `TODO.md`) : trop lourde pour une VM de 12 Gio sur disque rotatif (#79).
- **Hub → agent en SSH (port 45876)** à travers une ressource privée : ne
  publie rien, mais plus compliqué que le PASS à jeton.

## Conséquences

- Sur le LAN, l'UI de Beszel (port 8090 publié par Docker, avant ufw) répond
  sans SSO : seul le compte Beszel la protège.

## Liens

PR #854 (issue #79) ; issue #852 (agent de l'hôte Proxmox) ;
[architecture.md](../architecture.md) (« La supervision (Beszel) »),
`tofu/pangolin_config/websites.tf` (moniteurs), `cron_nas_cert.tf` (PikaPods).
