# healthlog

[HealthLog](https://github.com/MBombeck/HealthLog) sur la VM docker,
`https://sante.sylvain.cloud` : poids, composition corporelle, tension,
sommeil, activité, bilans de labo, avec l'intégration Withings (OAuth2) et
l'import de l'export Health Connect d'Android. PWA Next.js + PostgreSQL 18.

**Licence** : PolyForm Noncommercial 1.0.0 depuis la v1.15.18 (AGPL avant).
Usage personnel autorisé ; ni usage commercial, ni redistribution d'une
version modifiée à d'autres fins. À garder en tête si l'instance est un jour
partagée au-delà du foyer.

## Ce que déploie le rôle

- `compose.yaml` : `healthlog` (l'appli, web et worker dans un processus,
  `HEALTHLOG_PROCESS_TYPE=all`) sur `newt` et le réseau interne `healthlog`,
  `healthlog-db` (`postgres:18.6-alpine`) sur le réseau interne seul. Repris
  du `docker-compose.yml` amont de la v1.46.5, sans `db-upgrade` (passage
  Postgres 16 → 18 d'une ancienne installation) ni `db-restore` (profil
  `restore`, voir plus bas). Volumes nommés `healthlog_postgres_data` et
  `healthlog_backups` (dumps d'avant migration).
- `.env` (0600) : URL publique, clés dérivées, SMTP Infomaniak, appels
  sortants coupés (géolocalisation des IP de connexion chez ipwho.is,
  vérification de version sur GitHub).
- Sauvegarde borgmatic : dump de la base (`healthlog-db`) plus `compose.yaml`
  et `.env`. Le dump nocturne de HealthLog est coupé (`DB_BACKUP_ENABLED=false`),
  sa copie S3 jamais configurée ; le dump qu'il prend avant chaque migration
  reste, dans `healthlog_backups`, hors de borg (copie de travail pour un
  retour arrière).

Aucune clé SOPS : mot de passe de la base, `ENCRYPTION_KEY`,
`API_TOKEN_HMAC_KEY` et `WITHINGS_WEBHOOK_SECRET` sont dérivés de
`backup_passphrase` (sha256, un sel par secret), comme ceux de Dawarich.

## Premier démarrage

1. `tofu apply` dans `tofu/pangolin_config` (ressource, rôle SSO
   `healthlog`, moniteurs), puis le déploiement
   (`ansible-playbook docker.yml --tags healthlog`), puis
   `--tags homepage` pour le lien.
2. La première migration passe avant l'écoute (`start_period` de 10 min) :
   `docker logs -f healthlog` jusqu'à la bannière Next.js.
3. Ouvrir `https://sante.sylvain.cloud`, passer le SSO, **créer le compte** :
   le premier inscrit devient administrateur.
4. **Fermer l'inscription** : `/admin` → interrupteur d'inscription. Le SSO
   filtre déjà, mais rien ne sert de la laisser ouverte.
5. Activer la double authentification du compte (Paramètres → Sécurité).

## Accès

Derrière le SSO Pangolin, les règles pays (FR, DE) et le login de HealthLog.
Un seul chemin ouvert sans SSO, les notifications de Withings ; aucun jeton
d'accès Pangolin (`tofu/pangolin_config/website_healthlog.tf`).

- **Callback OAuth Withings** (`/api/withings/callback`) : une redirection
  de withings.com vers sante.sylvain.cloud, dans le navigateur de
  l'utilisateur, en GET de premier niveau. Le cookie de session Pangolin est
  `SameSite=Lax` (Pangolin 1.25.3, `server/auth/sessions/resource.ts`) : il
  part sur cette navigation, le callback passe le SSO comme n'importe quelle
  page. Session Pangolin expirée pendant le consentement : la page de
  connexion Pangolin, puis retour sur l'URL du callback (code encore valide).
- **Notifications Withings** (`/api/withings/webhook/<secret>`) : serveur à
  serveur, **ouvertes sans SSO et sans filtre pays** (Withings appelle depuis
  ses serveurs, sans session) : `ACCEPT` de `/api/withings/webhook/**`, un
  seul segment après `webhook/` (glob de segment de Pangolin), donc ni
  `/api/withings/webhook` lui-même, ni plus profond, ni le reste de
  `/api/withings/` (callback, connect, credentials, disconnect, status,
  sync), qui restent derrière le SSO. Ce qui protège : le secret dans le
  chemin (`WITHINGS_WEBHOOK_SECRET`, 64 caractères hexadécimaux dérivés de
  `backup_passphrase`), comparé en temps constant à chaque verbe, 401 sinon,
  débit limité. Withings ne signe rien et n'envoie aucun en-tête : ce
  secret est le seul contrôle. À la connexion, HealthLog s'abonne
  (`Notify.subscribe`), Withings vérifie l'URL en HEAD/GET (200), puis POSTe
  une notification à chaque mesure ; HealthLog va alors chercher les
  mesures dans l'API Withings avec son jeton, le corps ne fait que dire
  quoi chercher. La synchronisation horaire reste en filet (mesures à :00,
  sommeil à :15) ; l'ECG, sans notification (HealthLog n'abonne pas sa
  catégorie), n'arrive que par la sienne, à :41. Le secret est en clair dans
  le journal d'accès de Traefik sur Pangolin ; `log_agent` le masque avant
  VictoriaLogs (`log_agent_redactions`). Version relue :
  `path_bypass_images.json` (Renovate ne
  fusionne jamais une montée de HealthLog, les sources de `reread` sont
  relues avant).
- **Téléphone (PWA)** : le navigateur du téléphone passe le SSO comme le
  poste, puis le login HealthLog ; la PWA installée garde les cookies du
  navigateur. Un jeton d'accès Pangolin n'apporterait rien : le navigateur
  ne peut pas envoyer les en-têtes `P-Access-Token-*`, et `?p_token=` ne
  sert qu'à poser le même cookie de session (le `start_url` du manifeste
  est `/`, sans la requête). À l'expiration de la session Pangolin, se
  reconnecter au SSO.

## Withings

Les identifiants de l'appli développeur Withings se saisissent **par
utilisateur dans HealthLog**, chiffrés en base (`ENCRYPTION_KEY`) : pas de
variable d'environnement, pas de clé SOPS. Sans eux, HealthLog tourne,
Withings n'est simplement pas connecté.

1. <https://developer.withings.com/> → Partner Hub → créer une application
   **Public API** (plan gratuit « Start for Free » : poids, composition,
   tension, pouls, sommeil, pas ; pas la VOP, l'âge vasculaire ni l'ECG).
2. **Callback URL** : `https://sante.sylvain.cloud/api/withings/callback`
   (exactement, schéma compris).
3. Noter le **Client ID** et le **Client Secret** dans KeePassXC (entrée
   « Withings — HealthLog »). Le secret lit tout l'historique santé du
   compte lié : jamais dans un chat ni un ticket.
4. HealthLog → Paramètres → Intégrations → Withings : coller les deux,
   enregistrer, **Connecter Withings**, consentir sur withings.com
   (`user.metrics`, `user.activity`). Retour sur la page des intégrations,
   « Connecté » ; les 30 derniers jours sont importés.

Vérifier l'abonnement : se peser hors des minutes :00 à :05 ; la pesée doit
apparaître en quelques secondes, sans attendre la synchronisation horaire
(« Tester la connexion », dans le menu de la carte, ne vérifie que le jeton
OAuth, pas l'abonnement). Vérifier que le chemin passe le SSO, sans le vrai
secret (jamais sur une ligne de commande ni dans un ticket) :
`curl -sI https://sante.sylvain.cloud/api/withings/webhook/0` répond 401
(HealthLog), pas une redirection vers le SSO.

Rotation du secret client (fuite) : en régénérer un dans le Partner Hub,
le recoller dans HealthLog, reconnecter. Voir
`docs/runbooks/rotation-des-secrets.md`.

## Clé de chiffrement

`ENCRYPTION_KEY` chiffre les jetons Withings, les identifiants des
intégrations et le coffre de documents. Elle est dérivée de
`backup_passphrase` : **tourner `backup_passphrase` change cette clé**, et
HealthLog refuse alors de démarrer (contrôle de clé au démarrage) ou ne lit
plus ces colonnes. Avant une telle rotation, figer l'ancienne valeur :

```bash
printf '%s-healthlog-encryption' "$(sops decrypt --extract '["backup_passphrase"]' secrets/ansible.sops.yaml)" | sha256sum | cut -d' ' -f1
```

puis créer la clé SOPS `healthlog_encryption_key` avec ce condensat (elle
prime sur le défaut du rôle), ou passer par la rotation de HealthLog
(`ENCRYPTION_KEYS` + `ENCRYPTION_ACTIVE_KEY_ID`, `docs/ops/encryption-key-rotation.md`
de l'amont). Même chose pour `healthlog_db_password` (mot de passe de la
base, `docs/runbooks/mot-de-passe-base.md`) et `healthlog_api_token_hmac_key`
(la changer déconnecte tout le monde et invalide les jetons d'API). Le
secret du webhook (`healthlog_withings_webhook_secret`) peut, lui, changer,
mais **Déconnecter Withings avant** de déployer le nouveau secret, puis
Connecter après : la déconnexion désabonne l'URL bâtie sur le secret en
cours ; faite après le déploiement, elle viserait la nouvelle URL et
l'ancien abonnement resterait chez Withings, qui y enverrait chaque mesure
en 401.

Le `.env` est dans l'archive borg avec le dump : une restauration retrouve
la clé qui ouvre ce dump.

## Restauration

Le test de restauration (`.github/restore-test/apps.json`, `postgresql`)
rejoue le dump dans un `postgres:18.6-alpine` jetable. Restauration réelle :
`pg_restore` du dump borgmatic dans `healthlog-db`, appli arrêtée, avec le
`.env` de la même archive (commandes : `docs/runbooks/healthlog.md`,
« Restauration depuis Borg »). Le test de la CI ne démarre pas l'appli :
seule la restauration d'essai de ce runbook (appli jetable sur un réseau
interne, faite le 02/11/2026) prouve que la clé du `.env` ouvre les
colonnes chiffrées du dump. Les dumps d'avant migration de HealthLog
(`healthlog_backups`) se rejouent avec son service `db-restore` (profil
`restore` du compose amont, `docs/ops/disaster-recovery.md`).

## Mises à jour

Releases hebdomadaires, migrations de schéma au démarrage : Renovate
ouvre les PR (correctifs dans la PR hebdomadaire groupée, mineures une par
une), **jamais en fusion automatique** (appli à état, hors de la liste des
images sans état de `renovate.json`). Lire les notes de version, merger,
le déploiement suit (`deploy-docker-app`). Les montées majeures de
Postgres attendent le Dependency Dashboard.

## Import des pas (Health Connect)

Décision : export planifié de Health Connect vers kDrive, **import manuel**
par glisser-déposer. Rien d'automatisé, aucun jeton d'API HealthLog créé
(la route d'import n'accepte qu'un jeton complet, `*`). Le zip contient la
base Health Connect **en clair** : accepté sur kDrive.

Sur le téléphone (Pixel 7, une fois) :

1. Paramètres → Applications → Santé Connect (Health Connect) → Gérer les
   données → Exporter et importer (« Sauvegarde et restauration » selon la
   version) → **Export planifié**.
2. Destination : l'appli kDrive (fournisseur de stockage ; Health Connect
   refuse le stockage du téléphone lui-même), un dossier dédié, fréquence
   **hebdomadaire**.
3. Le premier export sort vide (bug connu) : vérifier que le second contient
   bien `health_connect_export.db` dans `Health Connect.zip`.

À chaque import (hebdomadaire, ou quand on veut) :

1. Télécharger `Health Connect.zip` depuis kDrive (web, appli de bureau ou
   téléphone).
2. HealthLog → Paramètres → Export & Import → carte **Health Connect
   export** : y déposer le zip. L'import tourne en tâche de fond, la carte
   suit son état (`GET /api/import/health-connect-export/status`) ; trois
   envois par minute au plus, 1 Gio maximum.
3. Supprimer la copie téléchargée sur le poste. HealthLog efface le zip et la
   base extraite à la fin de la tâche.

Ce que fait l'import : pas, calories actives et distance en un total par
jour (une seule appli par jour, la première de la liste de priorité de
Health Connect, sinon la plus grosse : pas de double comptage téléphone et
montre), sommeil, fréquence cardiaque, poids. Les enregistrements de
Withings présents dans l'export sont ignorés quand l'intégration Withings
est connectée. Réimporter le même fichier n'écrit rien (empreinte SHA-256) ;
un export plus récent n'ajoute que le neuf. Détail :
`docs/integrations/health-connect.md` de l'amont.
