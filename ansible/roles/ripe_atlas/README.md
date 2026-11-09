# ripe_atlas

Sonde logicielle [RIPE Atlas](https://atlas.ripe.net/) : la connexion de la
maison prête ses mesures (ping, traceroute, DNS, TLS, HTTP) au réseau de
mesures d'Internet du RIPE NCC. VM docker, `dc@ripe_atlas`, un conteneur
`ripe-atlas`. **Sortant seulement** : aucune ressource Pangolin, aucune route
publique, aucun port publié.

## Choix de l'installation

- **Image** : `jamesits/ripe-atlas` (communautaire, multi-arch, construite
  depuis les sources du RIPE NCC, version amont `5130`), plutôt que le paquet
  Debian officiel : il faudrait un hôte dédié ou un paquet installé par
  Ansible sur la VM, hors du modèle `dc@`. L'image est la seule option
  Docker ; le RIPE NCC n'en publie pas. Épinglée par tag et digest, Renovate
  la suit (PR hebdomadaire manuelle, pas dans la liste d'automerge).
- **Hôte : la VM docker**, pas le Pi (Blocky, DNS de tout le foyer, et
  Immich : une rafale de mesures n'a rien à y faire) ni le LXC newt (pas de
  Docker, le tunnel de la CI). La VM est limitée par les I/O disque, mais la
  sonde n'écrit presque rien : `/run/ripe-atlas` et `/var/spool/ripe-atlas`
  sont en `tmpfs`, seule la clé est sur disque. Réseau en pont par défaut
  (pas d'`host`) : telnetd (2023) et httppost (8080) restent dans le
  conteneur et ne heurtent aucun port de la VM ; la sonde est derrière le NAT
  de Docker en plus de celui de la box, sans effet sur ses mesures (l'exemple
  amont recommande l'hôte « si possible » pour éviter le double NAT).
- **Capacités** : `cap_drop: ALL` puis la liste de l'exemple amont
  (`NET_RAW`, `KILL`, `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, `DAC_OVERRIDE`).
  **Sans `no-new-privileges`** : le logiciel amont passe par des exécutables
  setuid et des capacités de fichier, que l'option bloque. Exception inscrite
  dans `docs/conventions/container-hardening.md` et `EXCEPTIONS` de
  `check_container_hardening.py`. Pas essayé avec l'option.
- **Ressources** : `mem_limit: 128m` (l'exemple amont : 64m), pas de `cpus:`.
  Pas encore mesuré : à recaler sur `memory.peak` (`mem_report`). Débit : de
  l'ordre de quelques centaines de Mo par mois, négligeable.

## Clé SSH : l'identité de la sonde

Au premier démarrage la sonde génère `probe_key` et `probe_key.pub` dans
`<docker_base_path>/ripe_atlas/etc` (monté sur `/etc/ripe-atlas`) : un
redéploiement ne change donc pas l'identité. Le dossier est rendu à l'uid
101 par l'entrypoint de l'image, d'où la lecture par `docker exec`.

**Sylvain lit la clé publique** (elle seule, jamais `probe_key`) :

```bash
docker exec ripe-atlas cat /etc/ripe-atlas/probe_key.pub
```

puis l'enregistre sur la page d'ajout de sonde logicielle de
atlas.ripe.net (compte RIPE NCC Access, adresse de la connexion et
emplacement à indiquer). Le RIPE traite la demande à la main : la sonde
apparaît dans le compte après un délai, et se connecte seule ensuite.

## Pas de sauvegarde

Volontaire, comme `pairdrop` : perdre la clé (disque de la VM perdu) oblige
seulement à enregistrer la nouvelle clé publique, ou à la demander au RIPE
pour la même sonde. La clé privée dans une archive Borg serait un secret de
plus à garder pour rien. Si la sonde accumulait un jour de l'historique
précieux, passer par le modèle partagé (`borgmatic`, `tasks_from: app.yml`).

## Supervision

Pas de moniteur Uptime Kuma : rien d'exposé à sonder, et la sonde n'a pas
de point de contrôle de son côté ; un arrêt se voit dans Beszel (conteneur
`ripe-atlas`) et sur la page de la sonde chez RIPE (statut « connected »).

## À vérifier au premier déploiement (non essayé ici)

- le conteneur démarre avec les `tmpfs` (l'exemple amont monte des dossiers
  de l'hôte) : `docker logs ripe-atlas`, `RestartCount` ;
- `probe_key.pub` apparaît dans le dossier.
