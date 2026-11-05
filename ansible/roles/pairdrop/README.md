# pairdrop

[PairDrop](https://github.com/schlagmichdoch/PairDrop) sur
**https://pairdrop.sylvain.cloud** : envoi de fichiers et de texte d'un
appareil à l'autre, en WebRTC pair à pair. VM docker, `dc@pairdrop`, un
conteneur `pairdrop` sur `newt`, derrière le SSO de Pangolin (rôle `pairdrop`,
sans membre : administrateurs Pangolin seulement).

Sans état : aucun volume, pas de sauvegarde, pas dans le test de restauration.

## Ce que dit la doc amont (« Host Your Own », v1.11.2)

- **HTTPS** : pas obligatoire pour le serveur, mais le navigateur l'exige pour
  copier un message reçu, installer la PWA, garder l'appairage et changer de
  nom. Pangolin (Traefik) termine le TLS.
- **WebSocket** : le canal de signalisation est un WebSocket ; le proxy doit
  laisser passer l'`Upgrade` (Traefik le fait sans réglage).
- **`X-Forwarded-For`** : le proxy doit le poser, sinon tous les clients se
  voient entre eux ; PairDrop groupe les appareils par IP publique. Traefik le
  pose. Non vérifié en production : après le déploiement, deux appareils du
  même foyer doivent se voir, un appareil en 4G non (`DEBUG_MODE=true` aide,
  jamais en production ; `/ip` n'existe qu'avec `RATE_LIMIT` actif).
- **IPv6** : `IPV6_LOCALIZE=4` réduit l'adresse IPv6 d'un client à son préfixe
  /64 ; sans lui, chaque appareil du foyer a sa propre adresse publique
  (extensions de confidentialité) et PairDrop les range dans des groupes
  différents.
- **Port** 3000 ; le serveur n'est publié nulle part (réseau `newt`).

## Limite : pas de serveur TURN

La doc amont : un TURN auto-hébergé (coturn, ports 3478, 5349 et 10000-20000)
est nécessaire pour les transferts entre réseaux différents. **Il n'est pas
ajouté** (décision de la tâche). Conséquences :

- STUN public de Google par défaut (`RTC_CONFIG` non défini) : les navigateurs
  contactent `stun.l.google.com` ;
- deux appareils d'un même réseau : fonctionne ; d'un réseau à l'autre
  (4G/CGNAT d'un côté, appairage par code), le transfert peut échouer faute de
  relais ;
- `WS_FALLBACK=false` (défaut) : le repli par le serveur ferait lire les
  fichiers par la VM ; à n'activer que sciemment.

Ajouter coturn sortirait du périmètre de ce rôle (ports UDP à ouvrir sur
Pangolin, identifiants dans SOPS, `rtc_config.json`).

## Durcissement

L'image démarre en root (`npm start`) ; le compose la lance sous l'uid de
déploiement en appelant `node server/index.js` directement, en lecture seule
(`tmpfs` sur `/tmp`), `cap_drop: ALL`, `no-new-privileges`. Essayé en local
(podman, même options) : démarre et répond 200. Pas essayé : un vrai transfert.

`mem_limit: 128m` est une valeur prudente, **à remesurer** (`memory.peak`,
rapport `mem_report`).

## Amont peu actif

Dernière version : v1.11.2 (février 2025). Pas dans la liste d'automerge de
Renovate (digest et patch arrivent dans la PR hebdomadaire).
