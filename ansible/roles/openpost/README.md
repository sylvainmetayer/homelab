# openpost

[OpenPost](https://github.com/getopenpost/openpost) (v7.38.6) sur
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
retour arrière autre que la sauvegarde.

## Premier démarrage

1. `tofu/pangolin_config` (skill `pangolin-config-plan`), puis
   `ansible-playbook flip.yml --tags openpost`.
2. T'ajouter au groupe `openpost` dans Pocket ID, ouvrir
   https://posts.sylvain.cloud et **créer le premier compte** : il est
   administrateur de l'instance. Utiliser la même adresse e-mail que ton
   compte Pocket ID.
3. Passer `openpost_disable_registrations: true` dans `host_vars/flip` et
   redéployer : plus d'inscription locale, les logins Pocket ID créent encore
   leur compte.
4. `ansible-playbook docker.yml --tags homepage` pour le lien sur Homepage.

## Connexion par Pocket ID (à la main, une fois)

OpenPost règle son SSO dans son interface, pas par variables, et ne le
documente pas : lu dans le code (`identity/service.go`, v7.38.6), **jamais
essayé ici**.

1. Lire le secret : `mise exec -- tofu -chdir=tofu/pangolin_config output -raw pocket_id_openpost_client_secret`.
2. Dans OpenPost, réglages de l'organisation, section SSO : ajouter un
   fournisseur OIDC, émetteur `https://id.sylvain.cloud`, client `openpost`,
   le secret, scopes `openid profile email`, création de compte à la première
   connexion (« JIT ») cochée pour le foyer.
3. Le rappel est `https://posts.sylvain.cloud/api/v1/auth/oidc/<id>/callback`,
   `<id>` étant créé par OpenPost à cette étape. Le client Pocket ID
   (`pocket_id.tf`) l'accepte par un joker (`/oidc/*/callback`). Si Pocket ID
   refuse le rappel, remplacer le joker par l'URL exacte et appliquer.
4. OpenPost exige un e-mail vérifié : c'est le cas des comptes Pocket ID.

Le mot de passe local (et les passkeys d'OpenPost) restent : c'est le secours
si Pocket ID est en panne, avec « mot de passe oublié » par mail.

## Médias : `/media/*` passe le mur, pas le contrôle d'OpenPost

Instagram, Threads, Facebook et TikTok téléchargent le média depuis leurs
serveurs : Pangolin ouvre `/media/*` sans SSO et depuis tout pays
(`tofu/pangolin_config/website_openpost.tf`), comme le demande la doc amont.
OpenPost garde la porte derrière (`handlers/media.go`, v7.38.6) : un média
(`/media/<uuid>`) ne sort qu'avec une session qui a accès à l'espace de
travail, ou par un lien signé à durée limitée (`sig`, `exp`), celui qu'il
remet aux réseaux. Sans l'un ni l'autre : 401. Relu à chaque montée de
l'image (`path_bypass_images.json`).

## Réseaux sociaux

Les identifiants se saisissent dans l'interface (Settings → Instance →
Configuration → Provider apps), chiffrés dans la base avec
`OPENPOST_ENCRYPTION_KEY` : rien dans SOPS. L'app développeur se crée à la main
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
| YouTube | console.cloud.google.com, client OAuth, API YouTube Data v3 | écran de consentement en « test » : jeton de 7 jours |
| LinkedIn | linkedin.com/developers | accès page à faire approuver à part |
| X | developer.x.com, OAuth 1.0a en écriture | offre gratuite très limitée ; OpenPost plafonne la dépense (`OPENPOST_X_MONTHLY_BUDGET_MICROUSD`) |
| TikTok | developers.tiktok.com, Login Kit et Content Posting API | preuve de propriété du domaine pour l'envoi par URL (`/media/`) |
| Pinterest, Telegram, bot Discord | — | pas dans le formulaire : JSON `OPENPOST_PROVIDER_APPS`, non câblé dans le rôle |

Bluesky (mot de passe d'application), Mastodon et les autres réseaux fédérés se
branchent depuis l'espace de travail, sans app développeur.

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
