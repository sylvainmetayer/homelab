# openwebui

[Open WebUI](https://github.com/open-webui/open-webui) (0.13.3, variante
`-slim`, publiée le 2026-11-08) sur **https://openwebui.sylvain.cloud** :
interface de chat pour le foyer. VM docker, `dc@openwebui`, un seul conteneur
`openwebui` (réseau `newt`). Derrière le SSO de Pangolin (rôle `openwebui`,
groupe Pocket ID du même nom : le foyer), puis la connexion à l'appli par
Pocket ID.

## Modèles : la passerelle IA de Pangolin, rien d'autre

Pas d'Ollama (`ENABLE_OLLAMA_API=false`, image sans), pas de RAG ni
d'embeddings locaux (image `-slim` sans torch, `BYPASS_EMBEDDING_AND_RETRIEVAL`:
un fichier joint est lu en entier dans le contexte), recherche web par un
SearXNG privé (section suivante), pas de génération d'images, exécution de code
ni partage communautaire, télémétrie coupée (`ANONYMIZED_TELEMETRY`, `SCARF_NO_ANALYTICS`, `DO_NOT_TRACK`, pas de
recherche de version).

- `OPENAI_API_BASE_URL=https://ia.sylvain.cloud/v1`, `OPENAI_API_KEY` = la clé
  virtuelle `openwebui` de `tofu/pangolin_config/ai_gateway.tf`
  (`terraform_outputs.ai_gateway_keys`), lue par le rôle (`defaults/main.yml`),
  comme Karakeep et Papra.
  **Clé absente du state** (avant l'apply de la clé) : le rôle rend
  `ENABLE_OPENAI_API=false`, aucune connexion IA, l'appli démarre quand même.
  Une rotation de la clé (`tofu apply -replace`, voir `ai_gateway.tf`) : relancer
  `docker.yml --tags openwebui`.
- Modèles `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`
  (`openwebui_ai_models`) : déclarés à la main dans `OPENAI_API_CONFIGS`
  (`model_ids`, dans `compose.yaml`: un JSON dans un `.env` dépend du lecteur).
  Open WebUI ne demande alors pas `/v1/models`, que la passerelle ne liste pas
  forcément. Modèle par défaut Sonnet ; titres des conversations par Haiku
  (`TASK_MODEL_EXTERNAL`) ; étiquettes, suites proposées et requêtes de
  recherche automatiques coupées : chaque génération compte dans les plafonds
  **en tokens** de la clé (5 M au total sur `lifetime`, bloquants : une fois
  atteints, le chat s'arrête jusqu'à ce qu'on relève le plafond à la main,
  `ai_gateway.tf`).
  Un dépassement se voit côté appli comme une erreur 429 de la passerelle.
- `ENABLE_PERSISTENT_CONFIG=false` : le `.env` est la source de vérité. Sans lui,
  Open WebUI garde en base ce qu'il a lu au premier démarrage (clé, modèles,
  OIDC) et ignore ensuite le fichier. Conséquence : un réglage fait dans
  **Admin → Paramètres** ne survit pas à un redémarrage. Ce qui reste en base :
  comptes, conversations, préférences et modèles personnalisés des personnes.
  Un réglage voulu durablement passe par une variable du rôle.

## Connexion : Pocket ID, mot de passe gardé

Client `openwebui` (`tofu/pangolin_config/pocket_id.tf`, groupe = rôle Pangolin
`openwebui`, PKCE S256, rappel `/oauth/oidc/callback`) ; le rôle relit
l'identifiant, le secret et l'émetteur dans les sorties Tofu (rien à saisir,
rien dans SOPS). Rendu seulement quand les trois existent (après l'apply de
`pangolin_config`, relancer `docker.yml --tags openwebui`).

- Inscription locale fermée (`ENABLE_SIGNUP=false`). Un compte naît au premier
  login Pocket ID (`ENABLE_OAUTH_SIGNUP`), rôle `user` (`DEFAULT_USER_ROLE`) ;
  seul le groupe Pocket ID filtre qui peut se connecter.
- **Sylvain se connecte le premier** : le premier compte de la base devient
  administrateur, quel que soit le chemin. Les promotions suivantes se font dans
  Admin → Utilisateurs (Open WebUI ne lit aucun rôle dans le jeton ici : pas
  de groupe `openwebui-admin`).
- Liaison d'un compte existant par e-mail (`OAUTH_MERGE_ACCOUNTS_BY_EMAIL`),
  **sans contrôle de `email_verified`** : sûr tant que seul l'administrateur
  crée les comptes Pocket ID et que `ALLOW_OWN_ACCOUNT_EDIT=false` (rôle
  `pocket_id`), comme Karakeep et MediaManager.

### Secours

Le formulaire e-mail / mot de passe reste actif (`ENABLE_LOGIN_FORM=true`) ;
un compte créé par OIDC a un mot de passe aléatoire inconnu.

1. Pocket ID injoignable, mais on est déjà administrateur ailleurs : Admin →
   Utilisateurs → le compte → champ « nouveau mot de passe », puis connexion
   par le formulaire. À faire **une fois pour le compte de Sylvain**, avant
   d'en avoir besoin.
2. Plus aucun accès : depuis l'hôte, poser un mot de passe dans la base
   (le conteneur tourne sous l'uid de déploiement, `webui.db` lui appartient) :

   ```bash
   docker exec -i openwebui python - <<'PY'
   import sqlite3, bcrypt
   db = sqlite3.connect("/app/backend/data/webui.db")
   h = bcrypt.hashpw(b"<mot de passe provisoire>", bcrypt.gensalt()).decode()
   print(db.execute("UPDATE auth SET password=? WHERE email=?", (h, "<adresse>")).rowcount)  # 1
   db.commit()
   PY
   ```

   (essayé en local sur la version épinglée, connexion par le formulaire
   ensuite). Changer le mot de passe aussitôt.
3. Pangolin lui-même : le compte propriétaire interne de l'organisation
   (`docs/runbooks/pocket-id.md`, « Secours »).

## Outil « journaux » : MCP de VictoriaLogs, pour Sylvain seul

Open WebUI interroge les journaux du homelab en langage naturel par le serveur
MCP officiel de VictoriaLogs (conteneur `mcp-victorialogs`, rôle
`victoria_logs`, README du rôle). Le rôle ne fait que déclarer la connexion :
`TOOL_SERVER_CONNECTIONS` (compose.yaml, comme les modèles ; `type: mcp`, URL
`http://mcp-victorialogs:8081/mcp`, sans authentification) et rejoindre le
réseau interne `victoria-logs-mcp`, créé par le compose de `victoria_logs`
(rôle placé avant celui-ci dans `docker.yml`, pour que le réseau existe).

- **Administrateurs seulement** : la connexion n'a pas de `access_grants`, et
  `has_connection_access` (v0.13.3, `utils/access_control`) réserve alors la
  connexion aux comptes `admin`. Le foyer (rôle `user`) ne la voit ni ne
  l'appelle.
- Le conteneur est sur un réseau interne partagé avec Open WebUI seul : `/mcp`
  n'a aucune authentification, c'est ce réseau qui la tient. Il lit par vmauth,
  avec un compte à jeton limité à `/select/logsql/.*`.
- Désactiver : `openwebui_mcp_victorialogs_enabled: false` **et**
  `victoria_logs_mcp_enabled: false` ensemble (le réseau n'existe plus sinon,
  Open WebUI ne démarre pas).
- **Pas de réglage dans l'interface** (`ENABLE_PERSISTENT_CONFIG=false`) : la
  connexion vient du compose, et reste en lecture seule dans
  Admin → Paramètres → Intégrations.
- À faire une fois : dans un chat, menu « + » (outils) → activer « Journaux
  (VictoriaLogs) » ; un modèle à appel d'outils fiable (Sonnet ou Opus).

## Sauvegarde

Borgmatic par le modèle partagé : `data/` (uploads ; `cache/` exclu, il se
retélécharge), `compose.yaml` et `.env` (clé de session, secret OIDC, clé de la
passerelle). La base `data/webui.db` est en WAL (défaut d'Open WebUI,
`DATABASE_ENABLE_SQLITE_WAL`) : le hook du rôle `borgmatic` en fait une copie
cohérente par `VACUUM INTO` dans le dossier de staging, sa copie vivante
exclue de l'archive ; jamais le `sqlite_databases` de borgmatic ni le fichier
vivant. Moniteur « Backup Open WebUI », test de restauration
(`.github/restore-test/apps.json`, tables `user` et `auth`).

À savoir au premier déploiement : `webui.db` n'existe qu'après le premier
démarrage (migrations) ; elle entre dans la configuration borgmatic au passage
suivant du rôle, et le test de restauration échoue « aucun dump ni copie
sqlite » d'ici là, puis « table attendue absente » tant que personne ne s'est
connecté (table `user` vide). Se connecter, puis relancer
`docker.yml --tags openwebui`.

## Recherche web : SearXNG privé, dans ce compose

Un second conteneur `searxng` (image officielle, étiquette + condensat dans
`openwebui_searxng_image`), **sans aucune exposition** : pas de ressource
Pangolin, pas de port publié, pas de réseau `newt`. Il ne sert qu'à Open WebUI.
Sans état : pas de sauvegarde (réglages dans `searxng/settings.yml` rendu par le
rôle, cache en tmpfs).

- Réseaux : `searxng` (`internal: true`, Open WebUI + SearXNG, aucune sortie) et
  `searxng-egress` (SearXNG seul, la sortie vers les moteurs). SearXNG n'est pas
  sur `newt` : ce réseau est partagé avec toutes les apps publiées.
- `settings.yml` : `search.formats` avec `json` (Open WebUI interroge
  `/search?format=json`), `server.limiter: false` (le limiteur exige Valkey ;
  un seul client interne, aucun besoin), `secret_key` dérivée de
  `app_secrets_seed` (`backup_passphrase` par défaut ; pas d'entrée SOPS), langue `fr`, `safe_search: 1`,
  moteurs `openwebui_searxng_engines` (peu, une seule IP domestique).
- Variables Open WebUI (relevées dans `config.py` v0.13.3 ; `ENABLE_RAG_WEB_SEARCH`
  est l'ancien nom) : `ENABLE_WEB_SEARCH=true`, `WEB_SEARCH_ENGINE=searxng`,
  `SEARXNG_QUERY_URL=http://searxng:8080/search`, `SEARXNG_LANGUAGE=fr`,
  `WEB_SEARCH_RESULT_COUNT`, `WEB_SEARCH_CONCURRENT_REQUESTS=1`.
  **Sans embeddings (image slim)** : `BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL=true`
  (`routers/retrieval.py`, `process_web_search` : les documents sont rendus tels
  quels au contexte au lieu d'être vectorisés) ; `BYPASS_WEB_SEARCH_WEB_LOADER=true`
  tant que `openwebui_web_search_load_pages` vaut false : seuls les extraits de
  SearXNG vont au modèle, Open WebUI ne télécharge aucune page (moins de tokens
  dans le plafond de la clé IA). Passer la variable à true pour lire les pages
  entières.
- La requête est le message de la conversation tel quel
  (`ENABLE_SEARCH_QUERY_GENERATION=false`, un appel IA de moins par recherche).
- À faire à la main : dans une conversation, activer le bouton « Recherche web »
  (ou le laisser par défaut dans les réglages du modèle). Les moteurs
  (`duckduckgo`, `google`, `startpage`, `wikipedia`) peuvent limiter ou bloquer
  une IP : si les résultats se vident, `docker logs searxng` et ajuster la liste
  (Brave était cassé à l'essai du 2026-11-09, d'où son absence).
- Renovate : image montée à la main comme le reste du rôle (pas d'automerge).
  Le conteneur tourne sous l'uid de déploiement, `read_only`, `cap_drop: ALL` : l'entrypoint
  ne change de propriétaire qu'en root et se contente d'un avertissement
  (« not owned by searxng ») dans les journaux.

## Durcissement et limites

`no-new-privileges`, `cap_drop: ALL`, sous l'uid de déploiement
(`docs/conventions/container-hardening.md`). L'image est construite pour root :
sous un autre uid, Open WebUI ne peut pas recopier ses fichiers de
personnalisation dans `/app/backend/open_webui/static` et journalise une
dizaine de lignes `Permission denied` à chaque démarrage. Sans effet (essayé
en local : migrations, connexion, liste des modèles). `mem_limit: 1200m` :
pic mesuré à 563 Mio en local (podman, premier démarrage avec toutes les
migrations, aucune conversation), 340 Mio au repos ; à recaler sur le pic
réel (`memory.peak`) après quelques jours. Pas de `cpus:` (pas de travail de
fond). Sonde : `/health` (200 sans compte) pour Pangolin et pour le conteneur
(`start_period` 180 s, migrations).

Renovate : pas d'automerge (appli à état dont l'image migre sa base au
démarrage), PR hebdomadaire manuelle ; une montée de minorité relit d'abord les
notes de version et `backend/open_webui/config.py`.
