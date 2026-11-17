# 0037. ntfy sur la VM Pangolin, hors de la maison

- **Statut** : acceptée
- **Date** : 2026-11-17

## Contexte

ntfy porte les notifications du homelab vers les téléphones : alertes d'Uptime Kuma, alertes de Pangolin (site hors ligne), scripts des hôtes, CI. Il tournait sur la VM docker, à la maison. Le 2026-11-17, une coupure de courant à la maison l'a emporté avec tout ce qu'il devait annoncer : seul Telegram pouvait encore prévenir (Uptime Kuma est chez PikaPods). Les alertes de Pangolin lui-même (`alerts.tf`, « Site hors ligne ») n'ont que ntfy pour canal : elles étaient perdues par construction dans le cas qu'elles visent.

ntfy est léger : un binaire Go, deux bases SQLite, 128 Mio de plafond, quelques dizaines de Kio de cache par jour.

## Décision

**ntfy tourne sur la VM Pangolin** (Hetzner), rôle `ntfy` appliqué par `pangolin.yaml` après le rôle `pangolin`, sur le modèle de Pocket ID : `/opt/ntfy`, `docker compose up -d` et la restart policy (pas de `dc@`), conteneur sur le réseau Docker `pangolin` de la pile, aucun port publié.

**Il reste une ressource Pangolin** (`local.websites`, `website_ntfy.tf`) : même nom, mêmes chemins ouverts, même SSO sur `/app`, mêmes moniteurs. Seule sa cible change : elle passe du site `proxmox-docker` au site `local` de l'instance (`pangolin_site.pangolin`), que Traefik sert directement en `http://ntfy:8080`, sans Newt. Une cible d'un site local n'est pas sondée par Pangolin (`hc_enabled = false`, dérivé du site dans `websites.tf`) : aucune sonde ne tourne sans Newt, et une cible créée avec sa sonde active reste `unhealthy`, donc retirée de Traefik.

Sauvegarde : dépôt Borg `ntfy` du sous-compte de Pangolin (gabarit partagé), test de restauration de la CI.

## Alternatives écartées

- **Le laisser à la maison** : c'est le défaut constaté. Un onduleur ne couvre ni la coupure d'Internet ni la panne de l'hôte Proxmox.
- **Sur flip** (l'autre VM Hetzner, avec Newt, `dc@` et sondes) : aucun changement de rôle ni de cible à inventer, mais flip porte la production de Flip Planning et n'a pas d'IP publique : ntfy y dépendrait de Pangolin **et** du Newt de flip, et sortirait vers ntfy.sh par le NAT de Pangolin. Deux hôtes à tenir debout au lieu d'un.
- **Un routeur Traefik écrit dans le rôle `pangolin`, comme Pocket ID** (hors ressource Pangolin) : ntfy survivrait à une panne du conteneur `pangolin` (Traefik garde sa configuration fichier, sans Badger). Écartée pour l'instant : on perd le SSO devant `/app`, le filtre FR/DE, les règles de chemins auditées, le moniteur et le lien Homepage générés, et tout cela serait à réécrire à la main dans Traefik. À reprendre si Pangolin (le conteneur) tombe un jour sans la VM.
- **ntfy.sh hébergé** : les messages (noms d'hôtes, alertes) sortiraient du homelab ; aujourd'hui ntfy.sh ne voit que des identifiants de message.

## Conséquences

- Bon : une coupure de courant ou d'Internet à la maison, ou la perte de l'hôte Proxmox, ne coupe plus ntfy ; « Site hors ligne » de Pangolin arrive enfin dans ce cas. Telegram reste le second canal.
- Bon : un saut de moins (plus de tunnel Newt entre Traefik et ntfy).
- Mauvais : ntfy et Pangolin tombent ensemble si la VM Pangolin tombe (c'était déjà vrai : ntfy est derrière Pangolin). Telegram, qui ne passe pas par Pangolin, couvre ce cas.
- Mauvais : 128 Mio de plus sur une VM de 4 Gio qui porte tout le trafic public ; plafond serré, à recaler sur `memory.peak`.
- Mauvais : pas de sonde Pangolin sur la cible, donc pas de page de maintenance automatique pour ntfy : ntfy arrêté, Traefik répond 502, que le moniteur Uptime Kuma lit comme DOWN.
- La première cible sur le site local : le test `probes_are_sparse_and_paused_apps_are_not_probed` fixe que ntfy est la seule, pour qu'une autre n'y perde pas sa sonde sans le dire.

## Liens

- `ansible/roles/ntfy/README.md`, `ansible/pangolin.yaml`, `tofu/pangolin_config/website_ntfy.tf`, `websites.tf` (`hc_enabled`), `alerts.tf`.
- Sources de Pangolin 1.26.0 lues pour la cible locale : `server/lib/traefik/loadBalancer.ts`, `server/routers/target/createTarget.ts` (`hcHealth`), `server/private/lib/traefik/getTraefikConfig.ts`.
- [0030](0030-pocket-id-fournisseur-identite-pilote.md) (Pocket ID, l'autre appli de la VM Pangolin), [0010](0010-supervision-beszel-uptime-kuma.md).
