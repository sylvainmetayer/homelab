# Carte du homelab

Les schémas d'ensemble, à lire avant le détail de
[architecture.md](architecture.md) : qui parle à qui, de la requête d'un
navigateur jusqu'au conteneur, et où partent les sauvegardes. Un clic sur un
schéma l'ouvre en grand.

Ce sont des fichiers SVG écrits à la main (`docs/schemas/`), du texte : un
hôte ou une appli qui change se corrige dans le fichier, par PR. Leurs
couleurs suivent le thème du système, pas celui du site.

## Vue d'ensemble

[![Tout le trafic public entre par la VM Pangolin ; chaque hôte de la maison et flip y ouvrent un tunnel WireGuard sortant ; chaque hôte sauvegarde vers la Storage Box.](schemas/carte-homelab.svg)](schemas/carte-homelab.svg)

Tout le trafic public entre par la VM Pangolin. La maison et flip n'écoutent
rien : leurs Newt ouvrent le tunnel vers Gerbil, et la requête redescend par
ce tunnel jusqu'au conteneur. Détail :
[le chemin d'une requête](architecture.md#le-chemin-dune-requete),
[les sauvegardes](architecture.md#les-sauvegardes), les applis et leur hôte
dans [apps.md](apps.md).

## Secrets et déploiement

[![secrets.sops.yaml alimente OpenTofu, appliqué à la main ; ansible.sops.yaml alimente Ansible, directement ou par la CI de déploiement.](schemas/secrets-deploiement.svg)](schemas/secrets-deploiement.svg)

Deux fichiers SOPS, deux chemins qui ne se croisent pas : les jetons cloud ne
servent qu'à OpenTofu, sur le poste de Sylvain ; la clé `github-actions` ne
déchiffre que `ansible.sops.yaml`. Détail :
[d'où vient chaque secret](architecture.md#dou-vient-chaque-secret),
[ce que déploie la CI](architecture.md#ce-que-deploie-la-ci-et-quand).

## Supervision et alertes

[![Chaque hôte envoie ses mesures au hub Beszel, ses journaux à VictoriaLogs et ses push à Uptime Kuma, qui sonde aussi les applis ; les alertes partent par e-mail, ntfy et Telegram.](schemas/supervision.svg)](schemas/supervision.svg)

Traits pleins : les mesures remontent. Tirets : les alertes partent. Uptime
Kuma est le seul à vivre hors de la maison : c'est lui qui voit la VM docker
tomber. Détail : [la supervision](architecture.md#la-supervision-beszel),
[les journaux](architecture.md#les-journaux-victorialogs).

## Le DNS de la maison

[![Les appareils interrogent deux instances de Blocky, qui résolvent les noms publics en DNS-over-TLS, renvoient les noms locaux à la Bbox et répondent 0.0.0.0 aux noms sur liste.](schemas/dns-maison.svg)](schemas/dns-maison.svg)

Deux Blocky pour qu'une panne de l'un passe inaperçue. Détail :
[le DNS de la maison](architecture.md#le-dns-de-la-maison-blocky),
[runbooks/dns-blocky.md](runbooks/dns-blocky.md).

## Le NAS, privé partout

[![À la maison, le nom public vise l'IP LAN du NAS ; dehors, le client Pangolin arrive par le Newt du NAS ; les deux chemins finissent au même Traefik, qui sert Jellyfin, UGOS et MediaManager.](schemas/nas-prive.svg)](schemas/nas-prive.svg)

Une seule adresse par appli, à la maison comme dehors, sans rien exposer sur
Internet. Le 443 passe par un relais séparé parce qu'il n'est à nous que tant
qu'UGOS ne le reprend pas. Détail :
[le chemin d'une requête](architecture.md#le-chemin-dune-requete), [media.md](media.md).
