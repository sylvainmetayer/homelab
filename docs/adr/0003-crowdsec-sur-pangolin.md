# 0003. CrowdSec sur Pangolin, plugin Traefik sur l'entrypoint

- **Statut** : acceptée
- **Date** : 2026-10-28

## Contexte

Les règles pays de Pangolin ([0002](0002-pangolin-seule-entree-publique.md))
laissent passer tout le trafic de FR et DE, scanners compris, jusqu'au SSO
ou aux chemins ouverts ; fail2ban ne surveille que sshd.

## Décision

- Conteneur `crowdsec` (agent + LAPI + AppSec) dans la pile Pangolin, qui lit
  le journal d'accès JSON de Traefik et tire la liste communautaire (CAPI).
- **Bouncer en plugin Traefik** (`crowdsec@file`) sur l'entrypoint
  `websecure`, avant Badger : toutes les routes HTTPS publiques. Mode
  `stream` (15 s) ; CrowdSec en panne laisse tout passer.
- **Bannissements actifs** (403), jamais pour `home_ip`, l'IP de Pangolin et
  les plages privées (liste blanche s02 et `clientTrustedIPs`).
- **AppSec en détection seule** : règles hors bande, alertes sans décision.
- **Pas de console**, pas de sshd ; IP vue : celle de la connexion.

## Alternatives écartées

- **`trustedIPs: 0.0.0.0/0`**, comme l'installateur de Pangolin : laisse
  usurper l'IP par `X-Forwarded-For`.
- **AppSec bloquant d'emblée** : chaque alerte serait un 403 ; le runbook
  demande de lire quelques semaines d'alertes avant de passer en bande.
- **Console CrowdSec** : écartée sans raison écrite dans #907 (à confirmer).

## Conséquences

- Une IP de cloud partagée (runners GitHub, Supabase, Uptime Kuma) peut être
  dans la liste communautaire : `pangolin_crowdsec_whitelist_extra` si besoin.
- Retour arrière : `pangolin_crowdsec_enabled: false`.

## Liens

PR #907 ; [runbooks/crowdsec.md](../runbooks/crowdsec.md).
