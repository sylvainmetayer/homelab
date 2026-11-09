# globalping_probe

Sonde du réseau [Globalping](https://globalping.io/) (jsDelivr) : n'importe
qui peut lancer depuis elle un ping, un traceroute, un mtr, un DNS ou une
requête HTTP. VM docker, `dc@globalping_probe`, un conteneur
`globalping-probe`. **Sortant seulement** (WebSocket vers l'API de
Globalping) : aucune ressource Pangolin, aucune route publique.

Sans état : aucun volume, pas de sauvegarde, pas dans le test de restauration.

## Choix de l'installation

- **Image** officielle `globalping/globalping-probe`, épinglée par tag
  (`0.54.0`) et digest ; Renovate la suit (PR hebdomadaire manuelle).
  L'image ne se met pas à jour seule : c'est Renovate qui la fait avancer.
- **Hôte : la VM docker** (voir le README de `ripe_atlas` : le Pi porte le
  DNS du foyer et Immich, le LXC newt n'a pas de Docker). Les tests sont
  ponctuels ; la doc amont dit la sonde « très légère » et ajuste sa
  capacité au nombre de coeurs et à la charge récente.
- **`network_mode: host`**, comme l'exemple amont : la sonde doit mesurer la
  connexion de la maison, pas le NAT de Docker. Rien n'écoute.
- **Capacités** : `cap_drop: ALL` + `NET_RAW` (ping, traceroute, mtr), l'image
  tournant en root sans autre besoin ; `no-new-privileges`, lecture seule,
  `tmpfs` sur `/tmp`. L'exemple amont n'ajoute aucune capacité (celles par
  défaut de Docker) ; la liste minimale est déduite des binaires de l'image,
  **pas essayée** : si un test échoue sans raison, regarder `docker logs
  globalping-probe` avant d'élargir.
- **Ressources** : `mem_limit: 256m`, pas de `cpus:` ; à recaler sur
  `memory.peak`. Débit : proportionnel aux tests demandés, bornés par
  Globalping.

## Adoption : dans le tableau de bord, sans secret

Une sonde non adoptée fonctionne déjà. Pour la rattacher à son compte
(crédits de test en plus), **à faire dans le tableau de bord**
(dash.globalping.io, « Probes », adoption à la main de la sonde vue sur
l'adresse IP publique de la maison), plutôt qu'avec la variable
`GP_ADOPTION_TOKEN` : le jeton serait un secret SOPS de plus (clé,
`secrets-rotation.yaml`, Molecule) pour une action qui se fait une fois.
Si un jour il le faut : clé SOPS préfixée `globalping_probe_`, passée en
`environment:` du compose (`0600`, `diff: false`).

## Supervision

Pas de moniteur Uptime Kuma : rien d'exposé à sonder. Beszel voit le
conteneur ; `docker logs globalping-probe` dit si elle est connectée.
