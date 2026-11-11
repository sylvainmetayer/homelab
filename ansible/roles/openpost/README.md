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
