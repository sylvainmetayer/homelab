# bentopdf

[BentoPDF](https://github.com/alam00000/bentopdf) (AGPL-3.0, version 2.8.11) sur
**https://bentopdf.sylvain.cloud** : outils PDF (fusion, découpe, compression,
conversions, signature, OCR...) qui tournent **dans le navigateur**. VM docker,
`dc@bentopdf`, un conteneur `bentopdf` sur `newt`, derrière le SSO de Pangolin
(rôle `bentopdf`, sans membre : administrateurs Pangolin seulement).

Sans état : aucun volume, pas de sauvegarde, pas dans le test de restauration.
Le serveur ne fait que servir des fichiers statiques (nginx) : les PDF ne
quittent jamais le navigateur, la VM ne les voit pas.

## Image

`ghcr.io/alam00000/bentopdf-simple` (officielle, publiée par le dépôt amont :
tous les outils, sans la vitrine commerciale de bentopdf.com). Épinglée par tag
et digest de l'index multi-architecture. La 2.8.11 a été publiée le
2026-10-31, soit plus de 3 jours avant l'ajout (`minimumReleaseAge`). Amont
actif (poussé le 2026-11-04), pas archivé. Licence AGPL-3.0, usage personnel
sans modification : aucune obligation ; la licence commerciale ne concerne que
le code fermé.

## OCR (français) : dans le navigateur, avec un CDN à l'usage

Résultat lu dans les sources (v2.8.11 : `Dockerfile`,
`src/js/utils/tesseract-runtime.ts`, `docs/self-hosting/docker.md`) et dans la
CSP que sert l'image (vérifiée sur le conteneur) :

- l'OCR est **Tesseract.js 7 (WebAssembly) exécuté par le navigateur**, pas par
  le serveur ; le français (`fra`) est dans le catalogue des langues
  (`src/js/config/tesseract-languages.ts`) ;
- les trois `VITE_TESSERACT_*` (worker, cœur WASM, données de langue) sont des
  arguments de **build** : l'image officielle les a vides, donc Tesseract.js
  utilise ses défauts, `cdn.jsdelivr.net` (`tesseract.js@v7.0.0`,
  `tesseract.js-core@v7.0.0`, `@tesseract.js-data/<langue>/4.0.0_best_int`). Le
  navigateur **télécharge donc les modèles depuis jsDelivr à l'usage** (le
  fichier `fra.traineddata.gz`, taille non mesurée, à chaque langue
  demandée ; le cache HTTP du navigateur les garde ensuite) ;
- la couche de texte des PDF océrisés charge ses polices Noto depuis
  `rawcdn.githack.com` (`VITE_OCR_FONT_BASE_URL` vide) ;
- les autres outils lourds (PyMuPDF, Ghostscript, CoherentPDF) chargent aussi
  leur WASM depuis `cdn.jsdelivr.net`, versions figées à la construction de
  l'image ; la CSP de l'image n'autorise que ces dossiers précis ;
- aujourd'hui Stirling-PDF fait l'OCR en français et en anglais sur le serveur,
  sans CDN : **BentoPDF fait la même chose, mais sans hors-ligne** (le
  navigateur doit pouvoir joindre jsDelivr) et sur le poste de l'utilisateur.
  Rendre cela hors-ligne exige de reconstruire l'image (arguments de build
  `VITE_TESSERACT_*`, `VITE_WASM_*`, `VITE_OCR_FONT_BASE_URL` vers un hôte
  interne) : non fait, une image maison sortirait du modèle « image officielle
  épinglée ».

**Non vérifié** : un OCR réel en français dans un navigateur (testé seulement :
l'image démarre, répond 200 et envoie la CSP attendue).

## Durcissement

L'image est `nginx-unprivileged` : elle tourne sans privilège. Le compose la
lance sous l'uid de déploiement, en lecture seule, `cap_drop: ALL`,
`no-new-privileges`, avec trois `tmpfs` : `/tmp`, `/etc/nginx/tmp` (pid de
nginx et `noindex.conf`) et `/var/cache/nginx` (caches temporaires ; sans lui
nginx s'arrête sur `mkdir() client_temp`). Essayé en local (podman, mêmes
options) : démarre, répond 200 avec `Cross-Origin-Opener-Policy: same-origin`
et `Cross-Origin-Embedder-Policy: credentialless` (requis par les conversions
Office, `SharedArrayBuffer`), le `wget --spider` du healthcheck passe.

`ROBOTS_NOINDEX=true` ajoute `X-Robots-Tag: noindex` (instance privée). `PORT`
et `DISABLE_IPV6` restent par défaut : les modifier fait réécrire
`/etc/nginx/nginx.conf` par le script d'entrée, impossible en lecture seule.

`mem_limit: 128m` est une valeur prudente (3 Mio au repos en local), **à
remesurer** (`memory.peak`, rapport `mem_report`).

## Mise à jour

Pas dans la liste d'automerge de Renovate : digest et mises à jour arrivent
dans la PR hebdomadaire.
