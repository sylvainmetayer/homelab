# openpost

[OpenPost](https://github.com/getopenpost/openpost) (v7.42.2) sur
**https://posts.sylvain.cloud** : planification de publications sur les réseaux
sociaux, pour le foyer. Hôte **flip**, `dc@openpost`, un seul conteneur
`openpost` (binaire Go, SQLite et médias sous `./data`, réseau `newt`).
Derrière le SSO de Pangolin (rôle `openpost`, groupe Pocket ID du même nom),
puis le login d'OpenPost.

Il remplace Postiz, essayé puis retiré le 2026-11-11 : sa pile (Temporal,
PostgreSQL, 1,6 Gio) ne tenait pas sur flip. La démo de Flip Planning est
restée en pause depuis cet essai (`docs/runbooks/app-en-pause.md`).

Projet jeune (premier commit en mars 2026) qui publie plusieurs versions par
semaine : Renovate les propose, jamais d'automerge (image de
`path_bypass_images.json`), et une montée migre la base au démarrage, sans
retour arrière autre que la sauvegarde. L'image est épinglée par digest (amont
ni signée ni attestée) et rien ne part vers l'amont : mise à jour, télémétrie et
diagnostics d'erreurs (`app.openpo.st`, allumés par défaut) sont coupés dans
`env.j2`.

## Premier démarrage

1. `tofu/pangolin_config` (skill `pangolin-config-plan`), puis
   `ansible-playbook flip.yml --tags openpost`.
2. T'ajouter au groupe `openpost` dans Pocket ID, ouvrir
   https://posts.sylvain.cloud et **créer le premier compte** : il est
   administrateur de l'instance. Utiliser la même adresse e-mail que ton
   compte Pocket ID.
3. Laisser l'inscription ouverte (`openpost_disable_registrations: false`) :
   `OPENPOST_DISABLE_REGISTRATIONS` ferme aussi la création de compte par un
   premier login Pocket ID (`identity/service.go`, `insertJITUser`, v7.38.6),
   pas seulement l'inscription par mot de passe. La page n'est atteinte que
   derrière le mur Pangolin, donc par le groupe `openpost` (décidé le
   2026-11-11).
4. `ansible-playbook docker.yml --tags homepage` pour le lien sur Homepage.

## Connexion par Pocket ID

Bouton « Pocket ID » sur la page de login : le fournisseur OIDC « d'instance »
d'OpenPost, posé par le rôle (`OPENPOST_OIDC_*`) depuis les sorties Tofu du
client `openpost` (`pocket_id.tf`). Rien à saisir. Rappel
`https://posts.sylvain.cloud/api/v1/auth/oidc/instance/callback`, PKCE,
e-mail vérifié exigé. Non documenté en amont : lu dans le code
(`config.go`, `identity/service.go`, v7.38.6).

- **Compte existant** (le tien, créé par mot de passe) : OpenPost ne relie pas
  par e-mail. Connecté en local, lier l'identité depuis le profil (sécurité,
  identités liées) ; ensuite le bouton ouvre ce compte.
- **Nouveau venu du foyer** : son premier login Pocket ID crée son compte
  (`OPENPOST_OIDC_JIT_ENABLED`), le groupe `openpost` est la barrière.
- **Ne pas passer le SSO en « obligatoire »** dans les réglages de
  l'organisation sans identité liée : tout l'espace de travail répond alors 403
  (vécu le 2026-11-11). Sortie : sur flip,
  `docker exec openpost sqlite3 /data/db/openpost.db "update organization_sso_policies set mode = 'disabled'"`.
  `OPENPOST_SSO_BREAK_GLASS_EMAILS` (non posé) exempte des comptes de cette
  obligation.
- Les fournisseurs créés à la main dans l'organisation (SSO d'organisation)
  sont un autre mécanisme, sans bouton sur la page de login : inutiles ici.

Le mot de passe local (et les passkeys d'OpenPost) restent : c'est le secours
si Pocket ID est en panne, avec « mot de passe oublié » par mail.

## Médias : `/media/*` passe le mur, pas le contrôle d'OpenPost

Instagram, Threads, Facebook et TikTok téléchargent le média depuis leurs
serveurs : Pangolin ouvre `/media/*` sans SSO et depuis tout pays
(`tofu/pangolin_config/website_openpost.tf`), comme le demande la doc amont.
OpenPost garde la porte derrière (`handlers/media.go`, v7.42.2) : un média
(`/media/<uuid>`) ne sort qu'avec une session qui a accès à l'espace de
travail, ou par un lien signé à durée limitée (`sig`, `exp`), celui qu'il
remet aux réseaux. Sans l'un ni l'autre : 401. Relu à chaque montée de
l'image (`path_bypass_images.json`).

## Réseaux sociaux

Les identifiants se saisissent dans l'interface (Settings → Instance →
Configuration → Provider apps), chiffrés dans la base avec
`OPENPOST_ENCRYPTION_KEY` : rien dans SOPS, sauf LinkedIn (plus bas). L'app développeur se crée à la main
chez chaque fournisseur ; l'URL de redirection est toujours

    https://posts.sylvain.cloud/api/v1/accounts/<réseau>/callback

(`facebook`, `instagram`, `threads`, `youtube`, `linkedin`, `x`, `tiktok` ; la
valeur exacte est dans le guide de chaque réseau,
`https://openpo.st/docs/self-hosting/integrations/<réseau>`, à recopier telle
quelle des deux côtés).

| Réseau | Où créer l'app | À savoir |
|---|---|---|
| Facebook (pages) | developers.facebook.com | pages seulement, pas de profil ; droit `pages_manage_posts` ; sans revue Meta, seuls les comptes ajoutés à l'app publient |
| Instagram | la même app Meta | compte professionnel, par login Instagram direct ou page Facebook liée |
| Threads | app « Threads API » | s'inviter comme testeur |
| YouTube | console.cloud.google.com, client OAuth, API YouTube Data v3 | écran de consentement en « test » : jeton de 7 jours ; projet non audité : vidéos privées |
| LinkedIn | linkedin.com/developers | profil seul ; identifiants dans SOPS, voir « LinkedIn » plus bas |
| X | developer.x.com, OAuth 1.0a en écriture | offre gratuite très limitée ; OpenPost plafonne la dépense (`OPENPOST_X_MONTHLY_BUDGET_MICROUSD`) |
| TikTok | developers.tiktok.com, Login Kit et Content Posting API | preuve de propriété du domaine pour l'envoi par URL (`/media/`) ; app non auditée : publication directe privée |
| Pinterest, Telegram, bot Discord | — | pas dans le formulaire : JSON `OPENPOST_PROVIDER_APPS`, non câblé dans le rôle |

Pas à pas de Facebook et d'Instagram (app Meta, permissions, test, dépannage),
de TikTok et de YouTube (écrits le 2026-11-16, pas encore essayés) :
`docs/runbooks/openpost-reseaux-sociaux.md`.

### LinkedIn

Seul réseau dont l'app passe par SOPS et non par l'interface : clés SOPS
`openpost_linkedin_client_id` et `openpost_linkedin_client_secret` (jamais de
défaut dans le rôle : une clé SOPS ne porte pas le nom d'une variable du
rôle), rendues en `LINKEDIN_CLIENT_ID` et
`LINKEDIN_CLIENT_SECRET` (`config.go`, v7.38.6). Dans Provider apps l'entrée
est en lecture seule ; les autres réseaux restent dans la base. Avec
`OPENPOST_DISABLE_LINKEDIN_THREAD_REPLIES=true` : l'app n'a que les produits
en libre-service, sans quoi la connexion du compte échoue ; pas de fil de
discussion. Les deux apps, la page LinkedIn créée pour elles, la demande
d'accès aux pages et la bascule :
`docs/runbooks/openpost-reseaux-sociaux.md`, « LinkedIn ».

Bluesky (mot de passe d'application), Mastodon et les autres réseaux fédérés se
branchent depuis l'espace de travail, sans app développeur.

## Banques d'images

La recherche d'images libres du sélecteur de médias s'allume dès qu'une de ces
clés SOPS existe (`OPENPOST_STOCK_MEDIA_ENABLED`, `templates/env.j2`) :

| Clé SOPS | Où la créer |
|---|---|
| `openpost_unsplash_access_key` | unsplash.com/oauth/applications, l'« Access Key » (pas la Secret key) ; 50 requêtes par heure en mode démo |
| `openpost_pixabay_api_key` | pixabay.com/api/docs, connecté |

Pexels (`OPENPOST_PEXELS_API_KEY`) n'est pas câblé. Chaque clé posée dans SOPS
a son entrée dans `secrets/secrets-rotation.yaml` (`docs/conventions/secrets.md`).
Le conteneur tourne en `TZ: Europe/Paris` (compose), comme les autres rôles.

## IA

Depuis la v7.40.2, OpenPost appelle une passerelle compatible OpenAI
(`OPENPOST_AI_BASE_URL`, il y ajoute `/chat/completions`) : ici la passerelle
IA de Pangolin, `https://ia.sylvain.cloud/v1`, clé virtuelle `openpost`
(`tofu/pangolin_config/ai_gateway.tf`, lue dans `terraform_outputs`), modèle
`claude-haiku-5-5` pour tout. Clé absente du state : le bloc n'est pas rendu,
l'IA reste éteinte : après l'`apply` de `tofu/pangolin_config` qui crée la clé,
relancer `flip.yml --tags openpost` (le merge déploie avant, sans clé). Les prompts passent par le journal de la passerelle
(90 jours).

Essayé le 2026-11-20 sur la passerelle, avec des requêtes au format de la
v7.42.2 (`response_format: json_schema` strict, `reasoning_effort`, image en
`data:`) :

| Fonction | État | Pourquoi |
|---|---|---|
| Texte alternatif d'une image | marche | image et sortie libre acceptées |
| « Raccourcir avec l'IA » | marche | schéma avec `minLength`/`maxLength` seulement, accepté |
| Génération de posts, angles, séries, mèmes, découverte, recyclage | **400** | leurs schémas portent `maxItems`, qu'Anthropic refuse |
| Décisions de workflow | **400**, éteintes (`OPENPOST_WORKFLOWS_AI_ENABLED=false`) | schéma avec `minimum`/`maximum` sur un nombre |

Les deux premières lignes sont déduites du schéma envoyé, pas encore essayées
dans l'appli. Le refus vient du point compatible OpenAI d'Anthropic, pas de
Pangolin (qui transmet tel quel) : signalé en amont à OpenPost. À une montée de
version, reprendre le tableau et rallumer les décisions si les schémas ont
changé. Génération d'images (fal, `FAL_KEY`) : non branchée.

## Mails

Compte Infomaniak partagé (`pangolin_smtp_*`, `OPENPOST_SMTP_*` du `.env`) :
mot de passe oublié, invitations, notifications. Changer `pangolin_smtp_pass` :
relancer aussi `flip.yml --tags openpost`.

## Sauvegarde

Borg `openpost` (sous-compte Storage Box de flip) : `data` (médias), la copie
SQLite d'`openpost.db`, `compose.yaml` et `.env`. Le `.env` porte
`OPENPOST_ENCRYPTION_KEY` (dérivée d'`app_secrets_seed`) : sans elle, les
identifiants des réseaux enregistrés dans la base ne se relisent pas.

## Mémoire

Plafond de 768 Mio, **non mesuré** (à recaler sur `mem_report`). ffmpeg tourne
dans le conteneur pour les vidéos.
