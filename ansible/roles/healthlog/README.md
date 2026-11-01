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
Aucun chemin ouvert sans SSO, aucun jeton d'accès Pangolin
(`tofu/pangolin_config/website_healthlog.tf`).

- **Callback OAuth Withings** (`/api/withings/callback`) : une redirection
  de withings.com vers sante.sylvain.cloud, dans le navigateur de
  l'utilisateur, en GET de premier niveau. Le cookie de session Pangolin est
  `SameSite=Lax` (Pangolin 1.25.3, `server/auth/sessions/resource.ts`) : il
  part sur cette navigation, le callback passe le SSO comme n'importe quelle
  page. Session Pangolin expirée pendant le consentement : la page de
  connexion Pangolin, puis retour sur l'URL du callback (code encore valide).
- **Notifications Withings** (`/api/withings/webhook/<secret>`) : serveur à
  serveur, **non ouvertes**. À la connexion, HealthLog s'abonne
  (`Notify.subscribe`) ; Withings vérifie l'URL par HEAD/GET, reçoit la
  redirection du SSO, l'abonnement échoue (classé transitoire) et HealthLog
  le retente avec un recul plafonné à 24 h. Les mesures arrivent quand même
  par la synchronisation horaire (mesures à :00, sommeil à :15, ECG à :41) :
  jusqu'à une heure de retard au lieu de quelques secondes. Ouvrir le
  webhook serait un `ACCEPT` mondial (Withings appelle depuis ses serveurs)
  du seul préfixe `/api/withings/webhook/*`, protégé par le secret de 64
  caractères hexadécimaux dans le chemin (401 sinon, débit limité) : à
  décider, pas fait.
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
(la changer déconnecte tout le monde et invalide les jetons d'API).

Le `.env` est dans l'archive borg avec le dump : une restauration retrouve
la clé qui ouvre ce dump.

## Restauration

Le test de restauration (`.github/restore-test/apps.json`, `postgresql`)
rejoue le dump dans un `postgres:18.6-alpine` jetable. Restauration réelle :
`pg_restore` du dump borgmatic dans `healthlog-db`, appli arrêtée, avec le
`.env` de la même archive. Les dumps d'avant migration de HealthLog
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

HealthLog importe nativement l'export de Health Connect (zip contenant
`health_connect_export.db`) : Paramètres → Export & Import → carte « Health
Connect export », ou `POST /api/import/health-connect-export`
(multipart, champ `file`). Pas, calories, distance, sommeil, fréquence
cardiaque, poids ; les enregistrements de Withings dans l'export sont
ignorés quand l'intégration Withings est connectée (pas de doublons), et
réimporter le même fichier n'écrit rien. L'automatisation (quel poste, quel
jeton) reste à décider : voir la PR qui a ajouté ce rôle.
