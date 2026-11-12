# Pangolin : Traefik resté arrêté après une mise à jour de Docker

## Symptôme

Le **12/11/2026 à 15:29**, `sudo apt install --only-upgrade docker-ce` sur la
VM Pangolin (le démon Docker redémarre). Tous les conteneurs sont revenus sauf
Traefik, resté `Exited (0)` : **aucun site public pendant 4 minutes**, jusqu'à
un `docker start traefik` à la main. Le journal de Traefik s'arrête sur son
arrêt propre (« I have to go… », code 0).

## Cause

Établi : Traefik a `restart: unless-stopped` et `network_mode: service:gerbil`
(réel : `container:<id de gerbil>`). À l'ouverture du démon, Docker relance les
conteneurs à restart policy un par un (`restore`, `daemon/daemon.go`). Un
démarrage qui échoue là est seulement journalisé (`failed to start container`) :
le conteneur reste `Exited`, la restart policy ne le reprend pas. Banc local
(Docker 29.9.3, démon dans podman) : un port de gerbil occupé au redémarrage du
démon fait échouer gerbil, puis Traefik (« cannot join network namespace of a
non running container: container gerbil is exited ») ; le port libéré, rien ne
les relance en 60 s, les deux restent `Exited (128)`.

Pas établi : pourquoi Traefik, ce jour-là, n'a pas démarré. Écartés sur le banc,
une vingtaine de redémarrages du démon en Docker 28.5.2 et 29.9.3, gerbil lent à démarrer
compris : Traefik repart à chaque fois (il attend que gerbil soit lancé). Deux
pistes : une course entre gerbil et Traefik dans `restore` (avant Docker 29,
l'attente de dépendance ne couvre que les `--link`, pas `container:`), ou un
échec propre à ce soir-là. La ligne `failed to start container` du journal de
`docker.service` de la VM le dirait (`sudo journalctl -u docker --since
15:25 | grep 'failed to start'`) : à confirmer, ni la version de Docker avant et
après la mise à jour ni ce journal ne sont dans le dépôt. Ce n'est ni
`restart: always` (même chemin de restauration) ni un arrêt jugé « voulu » :
Docker ne marque un conteneur « arrêté à la main » que hors arrêt du démon
(`daemon/kill.go`, `IsShuttingDown`).

## Ce qui a manqué

- Rien ne relançait Traefik après le démon : `pangolin.service` est un oneshot
  `Wants=docker.service` (pas `Requires=`, exprès : un `Requires=` arrêtait la
  pile avec le démon et rien ne la relançait), donc ne rejoue pas `compose up`
  au retour de Docker. Les hôtes `dc@` n'ont pas ce trou : leur `up` est en
  `Restart=always`.
- Le runbook de mise à jour ne demandait pas de vérifier Traefik sur Pangolin.

## Action

- Rôle `pangolin` : drop-in `docker.service.d/pangolin.conf`,
  `ExecStartPost=-docker start gerbil traefik`. Après chaque démarrage du démon
  (mise à jour, redémarrage, boot), ce qui n'est pas lancé l'est. Aucun
  conteneur recréé au déploiement.
- [mises-a-jour-hotes.md](../runbooks/mises-a-jour-hotes.md) : vérifier Traefik
  après Docker sur Pangolin, commande de relance.
- À confirmer : le journal de docker.service du 12/11 (cause exacte), la version
  de `docker-ce` avant et après.

Sources : `ansible/roles/pangolin/templates/pangolin.service.j2`, `compose.yaml`,
`docker-pangolin.conf.j2` ; moby `daemon/daemon.go`, `daemon/kill.go`,
`daemon/container.go` (tags 28.5.2 et 29.9.3).
