# La médiathèque (Jellyfin)

Films, séries, musique, livres et livres audio, servis par Jellyfin sur le NAS
Ugreen (rôle `ansible/roles/jellyfin`, playbook `ansible/nas.yml`). Chaque
personne du foyer a son propre compte Jellyfin, sans SSO. Ce document dit comment
s'y connecter, comment déposer des fichiers et comment les préparer pour qu'ils
se lisent sans transcodage.

## Les adresses

| Adresse | Où | À utiliser pour |
|---|---|---|
| `https://media.sylvain.cloud` | partout : à la maison, et dehors avec le client Pangolin connecté | **l'adresse de référence**, sans numéro de port (navigateur, nouvelles applis) |
| `https://media.sylvain.cloud:8443` | partout aussi | la même chose ; celle des applis déjà réglées, qui n'ont rien à changer, et le secours si le port 443 du NAS est repris par UGOS |
| `http://192.168.1.137:8096` | à la maison seulement | secours, quand l'adresse HTTPS ne répond plus ; **pas de cast** (il exige HTTPS) |

Pourquoi deux ports : le Traefik du NAS (rôle `nas_proxy`), qui sert
Jellyfin en HTTPS, écoute sur le **8443** du NAS depuis le début, et sur son
**443** depuis que la redirection HTTPS de l'interface d'UGOS est décochée
(cochée, le nginx d'UGOS prend le 443 pour renvoyer vers son interface). Si
une mise à jour d'UGOS la recoche, l'adresse sans port ne marche plus à la
maison, celle en `:8443` si : décocher à nouveau la case (voir
[architecture.md](architecture.md)).
Dehors, le client Pangolin passe par le Newt du NAS, qui joint ce Traefik
directement dans Docker, sur son 443 comme sur son 8443 : les deux adresses y
marchent toujours. Une appli réglée à la maison n'a donc rien à changer
dehors.

Le nom `media.sylvain.cloud` est un enregistrement DNS public qui vise l'IP
locale du NAS : rien n'est exposé sur Internet, mais les appareils qui
ignorent le DNS de la box (Chromecast, Google TV) le résolvent quand même.
C'est le contournement que la [documentation réseau de
Jellyfin](https://jellyfin.org/docs/general/networking/) recommande pour ces
appareils. Le certificat est un vrai certificat Let's Encrypt.

Dehors, il faut le client Pangolin connecté, avec un compte qui a le rôle
`jellyfin`. Détails techniques : [architecture.md](architecture.md) et
[apps.md](apps.md).

## Déposer des fichiers

Les médias vivent dans le dossier partagé SMB **`media`** du NAS, que Jellyfin
lit en lecture seule (il ne range ni ne supprime jamais rien) :

```
media/
├── films/
├── series/
├── musique/
├── livres/
└── livres-audio/
```

Une bibliothèque Jellyfin par dossier. Pour copier, renommer ou supprimer,
monter le partage sur le PC, depuis `ansible/` du dépôt :

```bash
ansible-playbook pc-nas.yml -K --tags mount    # monte media sur /mnt/nas/media
ansible-playbook pc-nas.yml -K --tags umount   # démonte
```

`-K` demande le mot de passe sudo du PC, puis le playbook demande le mot de
passe SMB du compte UGOS. Ça marche aussi dehors, client Pangolin connecté
(ressource `nas.sylvain.cloud`). Le montage ne survit pas à un redémarrage.

**Jamais par le gestionnaire de fichiers web d'UGOS** : il réécrit les
permissions des fichiers en `0600`, et Jellyfin peut ne plus les lire.

Après une copie, Jellyfin voit les nouveaux fichiers au prochain scan
(Tableau de bord → Bibliothèques → Scanner toutes les bibliothèques, ou
attendre le scan planifié).

Pour renommer en masse sur le PC : tinyMediaManager ou FileBot.

## Nommer les fichiers

Conventions de la documentation Jellyfin
([films](https://jellyfin.org/docs/general/server/media/movies/),
[séries](https://jellyfin.org/docs/general/server/media/shows/),
[musique](https://jellyfin.org/docs/general/server/media/music/),
[livres](https://jellyfin.org/docs/general/server/media/books/)).

### Films

Un dossier par film, `Titre (année)`, et des fichiers qui commencent
**exactement** par le nom du dossier :

```
films/
└── Film (2020)/
    ├── Film (2020) - 2160p.mkv     4K HDR, pour la TV
    ├── Film (2020) - 1080p.mkv     1080p SDR, pour le reste (voir plus bas)
    └── Film (2020) - 1080p.fr.srt  sous-titres externes de la version 1080p
```

Les deux fichiers sont deux **versions** du même film, pas deux films. Les
règles, d'après la doc :

- chaque fichier commence caractère pour caractère par le nom du dossier
  (année comprise), sinon Jellyfin en fait des films séparés ;
- l'étiquette (`2160p`, `1080p`) est séparée par un tiret, un point, un
  souligné ou mise entre crochets ; les espaces autour sont facultatifs ;
- une étiquette qui finit par `p` ou `i` est une résolution, et les
  résolutions sont triées de la plus haute à la plus basse : **la 2160p est la
  version proposée par défaut**. Sur le téléphone ou dehors, choisir « 1080p »
  dans le menu des versions avant de lancer la lecture.

Si l'identification se trompe, ajouter l'identifiant au nom du dossier **et**
des fichiers : `Film (2020) [imdbid-tt0000000]`.

### Séries

```
series/
└── Série (2019)/
    ├── Season 01/
    │   ├── Série S01E01.mkv
    │   └── Série S01E02.mkv
    └── Season 02/
        └── Série S02E01.mkv
```

Les dossiers de saison s'appellent `Season 01`, `Season 02`… (jamais `S01`),
numéro sur deux chiffres. Deux versions d'un épisode vont dans le même dossier
de saison : `Série S01E01 - 2160p.mkv` et `Série S01E01 - 1080p.mkv`.

### Musique

Un dossier par album, rangé par artiste : `musique/Artiste/Album/01 Titre.flac`.
Jellyfin lit surtout les tags des fichiers (artiste, album, numéro de piste,
disque), le nom de fichier ne sert qu'à défaut : bien taguer (MusicBrainz
Picard) compte plus que bien nommer. Éviter `< > : " / \ | ? *` dans les noms.

### Livres et livres audio

Un dossier par livre, éventuellement rangé par auteur :
`livres/Auteur/Livre/Livre.epub`, `livres-audio/Auteur/Livre/01.mp3`. Formats
lus : epub, pdf, mobi, azw3, cbz, cbr… La couverture peut être un `cover.jpg`
dans le dossier du livre.

## Ce qui force un transcodage

Jellyfin lit le fichier tel quel (« lecture directe ») quand l'appareil sait
le décoder. Sinon il convertit à la volée : seulement le conteneur
(« remux », quasi gratuit), l'audio (« direct stream », léger) ou la vidéo
(« transcodage », lourd, et en 4K HDR c'est le processeur graphique du NAS qui
s'y colle). Le tableau de bord (Activité, lectures en cours) et, dans le
lecteur, le menu ⚙ → informations de lecture disent lequel et pourquoi. Les
causes courantes :

| Cause | Exemple | Comment l'éviter |
|---|---|---|
| **HDR vers un écran SDR** | 4K HDR sur un téléphone, un navigateur, une vieille TV | lire la version **1080p SDR** ; Jellyfin ne fait pas HDR → HDR, il convertit toujours en SDR ([doc](https://jellyfin.org/docs/general/post-install/transcoding/)) |
| **Codec audio non supporté** | TrueHD, DTS vers Chromecast ou Google TV : le cast ne connaît que AAC, MP3, FLAC, Opus et AC-3/E-AC-3 en passthrough ([Google Cast](https://developers.google.com/cast/docs/media)) | piste **AAC stéréo** + piste **E-AC-3 5.1** dans la version 1080p |
| **Sous-titres image incrustés** | PGS (Blu-ray), VobSub (DVD) : un client qui ne sait pas les afficher les fait **graver dans la vidéo**, donc transcoder toute la vidéo | sous-titres **texte** (SRT) : intégrés au fichier ou à côté, `Film (2020) - 1080p.fr.srt` |
| **Débit au-dessus de la limite du client** | réglage « Qualité » de l'appli sur autre chose que le maximum, ou une 4K à 60 Mb/s sur une connexion mobile | régler la qualité de l'appli sur **Maximum/Automatique** à la maison ; dehors, la version 1080p |
| **Codec vidéo non supporté** | HEVC dans Firefox, AV1 sur un vieil appareil | H.264 pour la version 1080p ; Chrome/Edge plutôt que Firefox |

Un conteneur exotique (AVI, TS) ne fait que remuxer : pas grave, mais le MKV
évite même ça.

## Préparer la version 1080p SDR d'un film 4K HDR

À faire sur le PC (Fedora, `ffmpeg` de RPM Fusion, qui embarque `libplacebo`
et `zscale`), une fois par film. La version 2160p reste intacte pour la TV.
Commande vérifiée avec ffmpeg 8.1.3 (RPM Fusion, Fedora 44) sur un extrait HDR10
synthétique : sortie H.264 1080p BT.709, AAC stéréo, AC-3 5.1 copié,
sous-titres SRT et ASS copiés avec leurs polices.

```bash
ffmpeg -init_hw_device vulkan -i "Film (2020) - 2160p.mkv" \
  -map 0:v:0 -map 0:a:0 -map 0:a:0 -map 0:s? -map 0:t? \
  -vf "libplacebo=w=1920:h=-2:downscaler=ewa_lanczos:tonemapping=bt.2390:colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv:format=yuv420p" \
  -c:v libx264 -preset slow -crf 20 -profile:v high -level:v 4.1 \
  -c:a:0 aac -ac:a:0 2 -b:a:0 192k \
  -c:a:1 copy \
  -c:s copy \
  -disposition:a:0 default -disposition:a:1 0 \
  -metadata:s:a:0 title="Stéréo" \
  "Film (2020) - 1080p.mkv"
```

Option par option :

- `-init_hw_device vulkan` : `libplacebo` travaille sur le processeur graphique
  du PC, par Vulkan (tout GPU récent, NVIDIA compris, `vulkaninfo --summary`
  pour vérifier).
- `-map 0:v:0` : la première piste vidéo seule (pas les pochettes intégrées).
  `-map 0:a:0` **deux fois** : la piste audio principale, une fois pour la
  version stéréo, une fois pour la 5.1. `-map 0:s?` : tous les sous-titres,
  le `?` évite une erreur s'il n'y en a aucun. `-map 0:t?` : les pièces
  jointes du MKV, c'est-à-dire les polices des sous-titres ASS ; sans elles,
  des sous-titres stylés (animés, karaokés) s'affichent dans la police par
  défaut du lecteur. Pour une autre piste audio
  (VF plutôt que VO), `0:a:1`, etc. : `ffprobe "Film (2020) - 2160p.mkv"`
  liste les pistes.
- `libplacebo=` (le filtre vidéo, [doc
  ffmpeg](https://ffmpeg.org/ffmpeg-filters.html#libplacebo)) :
  - `w=1920:h=-2` : 1920 de large, hauteur calculée pour garder les
    proportions, arrondie au pair (un fichier en 3840×1608, film en 2,39:1
    sans bandes noires, donne du 1920×804 ; un 3840×2160 aux bandes noires
    incrustées, cas de la plupart des remux UHD, reste en 1920×1080 avec ses
    bandes) ;
  - `downscaler=ewa_lanczos` : réduction de bonne qualité (défaut `mitchell`,
    plus doux) ;
  - `tonemapping=bt.2390` : la conversion HDR → SDR (courbe BT.2390, la
    référence ; `auto` laisse libplacebo choisir). La mesure dynamique du pic
    (`peak_detect`) et les métadonnées Dolby Vision (`apply_dolbyvision`) sont
    actives par défaut ;
  - `colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv` : sortie
    en SDR BT.709 standard, plage limitée, et les étiquettes de couleur qui
    vont avec dans le fichier ;
  - `format=yuv420p` : 8 bits 4:2:0, ce que tout lecteur H.264 sait lire ; les
    images reviennent du GPU au processeur pour l'encodeur.
- `-c:v libx264 -preset slow -crf 20` : H.264, lisible partout (navigateurs,
  Firefox compris, Chromecast, téléphones). CRF 20 : qualité constante,
  quasi transparente en 1080p (18 = plus beau et plus gros, 22-23 = plus
  petit) ; compter souvent 5 à 12 Go pour un film de deux heures, selon le grain.
  `slow` gagne de la place contre du temps de calcul (`medium` pour aller plus
  vite).
- `-profile:v high -level:v 4.1` : le profil le plus répandu en 1080p, lu par
  tous les Chromecast.
- `-c:a:0 aac -ac:a:0 2 -b:a:0 192k` : première piste audio de sortie,
  réduite en **stéréo AAC 192 kb/s**, lue partout sans conversion.
- `-c:a:1 copy` : deuxième piste, la 5.1 d'origine **copiée** telle quelle.
  Seulement si elle est en AC-3 ou E-AC-3 (`ffprobe` l'affiche `ac3` ou
  `eac3`). Si c'est du TrueHD ou du DTS, la convertir en E-AC-3 5.1, que le
  cast et les TV passent à l'ampli :

  ```bash
    -c:a:1 eac3 -ac:a:1 6 -b:a:1 640k \
  ```

- `-c:s copy` : sous-titres copiés. Les sous-titres texte (SRT, ASS avec ses
  polices, voir `-map 0:t?`) ne posent aucun problème. Une piste PGS (image) est copiée aussi, mais elle
  forcera un transcodage si on la choisit : pour l'écarter, ajouter
  `-map -0:s:N` après `-map 0:s?` (N = son numéro parmi les sous-titres),
  et mettre plutôt un `.srt` à côté du fichier.
- `-disposition:a:0 default -disposition:a:1 0` : la stéréo est la piste par
  défaut (téléphone, casque), la 5.1 se choisit dans le lecteur.
- `-metadata:s:a:0 title="Stéréo"` : le nom affiché dans le menu des pistes.

Sans GPU Vulkan, la même chose au processeur, plus lent, avec `zscale` et le
filtre `tonemap` (courbe `hable`) : retirer aussi `-init_hw_device vulkan`,
sinon ffmpeg s'arrête avant de commencer (« Device creation failed »), et
remplacer la ligne `-vf` par :

```bash
  -vf "zscale=w=1920:h=-2:filter=spline36,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p" \
```

Elle ne sait pas appliquer les métadonnées Dolby Vision : un fichier en Dolby
Vision profil 5 (sans couche HDR10) sort avec des couleurs fausses, seul
`libplacebo` le traite correctement.

HEVC (`-c:v libx265 -preset medium -crf 22`) donnerait un fichier plus petit
d'un tiers environ, mais Firefox et les vieux appareils ne le lisent pas : la
version 1080p est celle « qui marche partout », H.264 reste le bon choix.

Vérifier le résultat :

```bash
ffprobe -v error -show_entries stream=index,codec_name,width,height,color_transfer,channels -of compact "Film (2020) - 1080p.mkv"
```

attendu : `h264`, `1920`, `color_transfer=bt709`, une piste `aac` à 2 canaux,
la 5.1, les sous-titres.

## Caster

Le cast (Google Cast) vers la TV ou un Chromecast ne marche **qu'en HTTPS**,
donc seulement sur `https://media.sylvain.cloud` (avec ou sans `:8443`),
jamais sur `http://192.168.1.137:8096`.

- **Navigateur** : Chrome, Chromium ou Edge, sur l'adresse HTTPS. Firefox
  n'a pas Google Cast : l'icône affiche « Google Cast non pris en charge ».
- **Android** : l'appli Jellyfin **du Google Play Store**. Celle de F-Droid
  est la version libre, livrée **sans** Google Cast ([README de
  l'appli](https://github.com/jellyfin/jellyfin-android)).
- **Google TV** : elle a sa propre appli Jellyfin (Play Store de la TV), à
  préférer au cast : elle lit plus de formats en direct. La TV est aussi une
  cible de cast depuis le téléphone ou Chrome.

## Les applis

| Appareil | Appli | Réglage |
|---|---|---|
| Google TV | Jellyfin (Play Store de la TV) | serveur `https://media.sylvain.cloud:8443` (indépendant du réglage d'UGOS) |
| Téléphone Android | Jellyfin (Google Play, pour le cast) | serveur `https://media.sylvain.cloud:8443`, qui marche aussi dehors avec le client Pangolin connecté |
| Dehors | client Pangolin connecté, puis l'appli ou le navigateur | même adresse ; choisir la version 1080p |
| Navigateur | Chrome, Chromium ou Edge | `https://media.sylvain.cloud` |
| Musique sur Android | Symfonium (payant, le plus complet, hors ligne), Finamp (libre), ou l'appli Jellyfin | même serveur ; Finamp et Symfonium savent télécharger pour le hors ligne |
| Livres | le lecteur intégré de Jellyfin (navigateur ou appli) | rien à installer |

## Réglages du serveur

Faits :

- **Proxys connus** (Tableau de bord → Réseau) : `172.30.96.10`, l'IP fixe
  du Traefik devant Jellyfin. Sans elle, Jellyfin voit toutes les connexions
  venir de Traefik et ignore les vraies adresses des clients.

Faits le 2026-11-02 (Tableau de bord → Lecture → Transcodage), d'après la [doc Intel de
Jellyfin](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel/) et ce
que `vainfo` rapporte sur le NAS (N100, pilote iHD) ; détail et commandes de
contrôle dans le README du rôle `jellyfin` :

- Accélération matérielle : **Intel QuickSync (QSV)** ; périphérique QSV :
  `/dev/dri/renderD128`.
- Décodage matériel, coché : H264, HEVC, MPEG2, VC1, VP8, VP9, AV1, HEVC
  10 bits, VP9 10 bits, HEVC RExt 8/10 bits, HEVC RExt 12 bits.
- « Préférer les décodeurs matériels natifs DXVA ou VA-API » : coché (requis
  pour Dolby Vision).
- Encodage matériel activé ; « Autoriser l'encodage au format HEVC » : coché ;
  AV1 : décoché (le N100 décode l'AV1 mais ne l'encode pas). Encodeurs
  Low-Power H.264/HEVC : cochés (le journal d'un transcodage montre
  `h264_qsv -low_power 1`).
- Tone mapping : activé, en **OpenCL** (vérifié disponible dans le conteneur :
  « Intel(R) OpenCL Graphics »), qui gère aussi Dolby Vision profil 5 ; VPP
  décoché.

Vérifier ensuite : lire un film 4K HDR dans Chrome sur le PC (écran SDR), puis
Tableau de bord → Activité : la lecture doit indiquer un transcodage
matériel, et `top` sur le NAS ne doit pas montrer `ffmpeg` à 400 %.

## En cas de problème

- L'adresse HTTPS ne répond plus à la maison : essayer
  `http://192.168.1.137:8096`. Si elle répond, c'est Traefik ; ses erreurs
  (requêtes en 4xx/5xx, à l'heure locale, sans paramètres ni en-têtes, donc
  sans jeton ; seule exception, une révocation de clé d'API qui échoue laisse
  la clé dans le chemin) sont dans `sudo docker logs nas-proxy` sur le NAS
  (unité `dc@nas_proxy`).
- Plus rien ne répond : `systemctl status dc@jellyfin` sur le NAS (unité
  système), et le runbook [appli en panne](runbooks/appli-en-panne.md).
