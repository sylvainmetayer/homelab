# HealthLog (sante.sylvain.cloud) : appli ou base en panne, Withings ne synchronise plus

Rôle `healthlog`, VM docker, `dc@healthlog`, dossier `/opt/apps/healthlog`.
Deux conteneurs : `healthlog` (web et worker dans un processus) et
`healthlog-db` (PostgreSQL 18, réseau interne seulement). Détail :
[README du rôle](../../ansible/roles/healthlog/README.md).

## Symptôme

- Moniteur « Healthcheck HealthLog » DOWN, page de maintenance de Pangolin
  sur `https://sante.sylvain.cloud`.
- Ou : les pesées Withings n'arrivent plus, ou seulement à l'heure pleine
  (la synchronisation horaire rattrape, le webhook ne marche plus).
- Ou : après une rotation de `backup_passphrase`, HealthLog ne démarre plus
  (contrôle de la clé de chiffrement au démarrage).

## Diagnostic

```bash
cd ansible && mise run ssh
systemctl --user status dc@healthlog
cd /opt/apps/healthlog && docker compose ps
docker logs --tail 200 healthlog
docker logs --tail 50 healthlog-db
```

- `healthlog` en `starting` pendant plusieurs minutes après une montée de
  version : migrations avant l'écoute, jusqu'à ~8 min (`start_period` de
  10 min). Attendre la bannière Next.js avant de conclure.
- `healthlog-db` pas `healthy` : `healthlog` ne démarre pas
  (`depends_on: service_healthy`). Mémoire (`mem_limit: 1g`) :
  `docker stats --no-stream healthlog-db`.
- Erreur de clé au démarrage (`ENCRYPTION_KEY`) : voir « Clé de
  chiffrement » plus bas.

Withings, du plus probable au moins probable :

1. **Le jeton OAuth** : HealthLog → Paramètres → Intégrations → Withings,
   « Tester la connexion » (ne vérifie que le jeton, pas l'abonnement).
2. **Le chemin du webhook passe-t-il le SSO ?** Sans le vrai secret (jamais
   sur une ligne de commande) :

   ```bash
   curl -sI https://sante.sylvain.cloud/api/withings/webhook/0
   ```

   Attendu : `401` de HealthLog. Une redirection `302` vers le SSO de
   Pangolin : l'ouverture `ACCEPT` de `/api/withings/webhook/**` a disparu
   (`healthlog_withings_webhook_paths`,
   `tofu/pangolin_config/website_healthlog.tf`) ; `mise exec -- tofu
   -chdir=tofu/pangolin_config plan` la montre.
3. **Les appels de Withings arrivent-ils ?** Dans VictoriaLogs (journal
   d'accès de Traefik sur Pangolin, secret masqué par `log_agent`), ou
   `docker logs healthlog 2>&1 | grep -i withings`. Des `401` en série :
   Withings appelle une ancienne URL (secret du webhook changé sans
   Déconnecter avant, plus bas).
4. **La synchronisation horaire** (mesures à :00, sommeil à :15, ECG à :41)
   tourne-t-elle ? Si elle aussi échoue, le problème est le jeton ou l'API
   Withings, pas le webhook.

## Réparation

- **Conteneur planté** : `systemctl --user restart dc@healthlog`. Le reste :
  [appli-en-panne.md](appli-en-panne.md).
- **Ouverture du webhook disparue** : `tofu apply` dans
  `tofu/pangolin_config` (Sylvain), après lecture du plan.
- **Jeton Withings expiré ou révoqué** : Intégrations → Withings →
  **Déconnecter**, puis **Connecter Withings** et consentir sur
  withings.com. HealthLog se réabonne au webhook à la connexion.
- **Secret du webhook changé** (dérivé de `backup_passphrase`, ou clé SOPS
  `healthlog_withings_webhook_secret`) : l'ancien abonnement reste chez
  Withings. Toujours **Déconnecter avant** de déployer le nouveau secret,
  **Connecter après**. Déjà fait dans le mauvais ordre : l'abonnement à
  l'ancienne URL reste chez Withings, qui y envoie chaque mesure en `401`
  (sans effet sur les données). Pour le retirer : remettre l'ancien secret
  (clé SOPS `healthlog_withings_webhook_secret`), déployer, Déconnecter,
  puis déployer le nouveau et Connecter.
- **Secret client Withings fuité** : en régénérer un dans le Partner Hub,
  le recoller dans HealthLog, reconnecter
  ([rotation-des-secrets.md](rotation-des-secrets.md)).

### Clé de chiffrement

`ENCRYPTION_KEY` (jetons Withings, identifiants des intégrations, coffre de
documents), le mot de passe de la base, la clé HMAC des jetons d'API et le
secret du webhook sont **dérivés de `backup_passphrase`** (sha256 salé,
`defaults/main.yml`). Tourner `backup_passphrase` les change tous au
déploiement suivant.

**Avant** la rotation, figer les anciennes valeurs (depuis la racine du
dépôt) :

```bash
printf '%s-healthlog-encryption' "$(sops decrypt --extract '["backup_passphrase"]' secrets/ansible.sops.yaml)" | sha256sum | cut -d' ' -f1
```

puis la clé SOPS `healthlog_encryption_key` avec ce condensat (elle prime sur
le défaut du rôle), avec son entrée dans `secrets/secrets-rotation.yaml`.
Même chose avec les sels `-healthlog-db` (`healthlog_db_password`, sinon
[mot-de-passe-base.md](mot-de-passe-base.md)), `-healthlog-api-token-hmac`
(`healthlog_api_token_hmac_key`, sinon tous les jetons d'API tombent) et
`-healthlog-withings-webhook` (`healthlog_withings_webhook_secret`, sinon
Withings garde l'abonnement à l'ancienne URL et le webhook se tait : sans
le figer, Déconnecter Withings avant le déploiement, Connecter après).

**Rotation déjà déployée, HealthLog ne démarre plus** : l'ancienne
`ENCRYPTION_KEY` est dans le `.env` de la dernière archive borg d'avant le
déploiement :

```bash
sudo -i
borgmatic=/root/.local/bin/borgmatic
config=/etc/borgmatic.d/healthlog.yaml
$borgmatic list --config $config
mkdir -p /root/restore/healthlog
$borgmatic extract --config $config --archive <archive d'avant> --destination /root/restore/healthlog
grep -E '^(ENCRYPTION_KEY|API_TOKEN_HMAC_KEY|WITHINGS_WEBHOOK_SECRET|DATABASE_URL)=' /root/restore/healthlog/opt/apps/healthlog/.env
```

Le mot de passe de la base est celui de `DATABASE_URL` (entre `healthlog:`
et `@`) : la base garde l'ancien (`POSTGRES_PASSWORD` n'est lu qu'à
l'initdb), donc sans lui HealthLog ne s'y connecte plus, clé ou pas.
Recopier ces valeurs dans les clés SOPS ci-dessus (depuis le poste,
`sops set --value-stdin`, jamais en argument), puis
`ansible-playbook docker.yml --tags healthlog`. Supprimer
`/root/restore/healthlog` ensuite.

### Restauration depuis Borg

L'archive contient le dump de la base **et** `compose.yaml` + `.env` : le
`.env` porte la clé qui ouvre les colonnes chiffrées du dump. Procédure
générale : [../backup-restore.md](../backup-restore.md) ; pour HealthLog,
l'appli doit rester arrêtée pendant le `pg_restore` (sinon elle migre ou
écrit dans la base pendant la restauration) :

```bash
systemctl --user stop dc@healthlog
# en root : extract comme ci-dessus (--archive latest), puis remettre en place
sudo cp -a /root/restore/healthlog/opt/apps/healthlog/. /opt/apps/healthlog/
# en sylvain : la base seule
cd /opt/apps/healthlog && docker compose up -d healthlog-db
docker compose ps healthlog-db        # attendre healthy
# en root
sudo /root/.local/bin/borgmatic restore --config /etc/borgmatic.d/healthlog.yaml --archive latest
# en sylvain : arrêter la base hors de dc@, puis l'unité reprend tout
docker compose stop && systemctl --user start dc@healthlog
```

Le `.env` restauré ne survit pas au déploiement suivant s'il diffère de celui
que dérive `backup_passphrase` : figer d'abord les clés dans SOPS (plus
haut). Les dumps d'avant migration (`healthlog_backups`, hors borg) se
rejouent avec le service `db-restore` du compose amont
(`docs/ops/disaster-recovery.md` de HealthLog).

`borgmatic restore` rejoue le dump avec le `pg_restore` **de l'hôte**
(Debian 13 : 17.11), pas celui du conteneur : il lit les dumps de
PostgreSQL 18.6 (format d'archive 1.16), vérifié le 02/11/2026. S'il
refuse un jour le dump (`unsupported version … in file header`, après une
montée de Postgres), le rejouer avec le client du conteneur, depuis le dump
extrait (borgmatic 2.1 le met dans l'archive, au format custom, sous
`borgmatic/postgresql_databases/<conteneur>:<port>/<base>`) :

```bash
# en root, après l'extract ; healthlog-db démarré, appli arrêtée
cat '/root/restore/healthlog/borgmatic/postgresql_databases/healthlog-db:5432/healthlog' \
  | docker exec -i healthlog-db pg_restore -U healthlog -d healthlog --clean --if-exists --exit-on-error
```

### Restauration d'essai (sans toucher à l'appli)

Faite le 02/11/2026 sur la VM docker, ~3 min en tout (extract 6 s,
restore 12 s). Tout dans un dossier `0700` de root et des conteneurs
jetables : ni l'appli, ni sa base, ni `newt`. En `sylvain`, depuis
`mise run ssh` :

```bash
sudo install -d -m 0700 /root/restore-drill/healthlog
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/healthlog.yaml extract \
  --archive latest --destination /root/restore-drill/healthlog
# base jetable : même image que le rôle, données en tmpfs, aucun port publié,
# réseau bridge par défaut (borgmatic la joint par son IP), sans mot de passe
docker run -d --rm --name drill-healthlog-db --network bridge --memory 768m \
  --mount type=tmpfs,destination=/var/lib/postgresql,tmpfs-size=1073741824 \
  -e POSTGRES_USER=healthlog -e POSTGRES_DB=healthlog -e POSTGRES_HOST_AUTH_METHOD=trust \
  "$(grep -m1 -o 'postgres:[^ ]*' /opt/apps/healthlog/compose.yaml)"
until docker exec drill-healthlog-db pg_isready -q -h 127.0.0.1 -U healthlog; do sleep 2; done
# --container détourne la restauration vers la base jetable
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/healthlog.yaml restore \
  --archive latest --container drill-healthlog-db
```

Comparer les lignes de chaque table avec la base vivante (lecture seule) :

```bash
q='select table_schema||$$.$$||table_name, (xpath($$/row/c/text()$$, query_to_xml(format($$select count(*) as c from %I.%I$$, table_schema, table_name), false, true, $$$$)))[1]::text::bigint from information_schema.tables where table_type=$$BASE TABLE$$ and table_schema not in ($$pg_catalog$$,$$information_schema$$) order by 1'
diff <(docker exec -e PGOPTIONS='-c default_transaction_read_only=on' healthlog-db psql -U healthlog -d healthlog -AtF' ' -c "$q") \
     <(docker exec drill-healthlog-db psql -U healthlog -d healthlog -AtF' ' -c "$q")
```

Seules diffèrent les tables écrites depuis la nuit (`pgboss.job*`,
`host_metrics`, `database_backup_runs`).

**La clé ouvre-t-elle les colonnes chiffrées ?** Au démarrage, HealthLog
déchiffre sa ligne témoin (`encryption_key_canaries`, `v1`, chiffrée avec
`ENCRYPTION_KEY`) et répond 503 partout si elle ne s'ouvre pas. Démarrer
l'appli jetable sur la base restaurée, avec le `.env` de l'archive, sur un
réseau **interne** (ni Internet, donc ni Withings ni SMTP), en mode `web`
(pas de worker) :

```bash
docker network create --internal drill-healthlog
docker network connect drill-healthlog drill-healthlog-db
sudo docker run -d --rm --name drill-healthlog-app --network drill-healthlog \
  --memory 1536m --cap-drop ALL --security-opt no-new-privileges:true \
  --env-file /root/restore-drill/healthlog/opt/apps/healthlog/.env \
  -e DATABASE_URL=postgresql://healthlog:drill@drill-healthlog-db:5432/healthlog \
  -e HEALTHLOG_PROCESS_TYPE=web -e SMTP_HOST= -e DB_BACKUP_BEFORE_MIGRATE=false \
  "$(grep -m1 -o 'ghcr.io/mbombeck/healthlog:[^ ]*' /opt/apps/healthlog/compose.yaml)"
sleep 40   # migrations (aucune en attente) et contrôle de clé
docker exec drill-healthlog-app wget -q -O - http://127.0.0.1:3000/api/health
```

`{"status":"ok"}` : la clé de l'archive ouvre le dump. Contre-épreuve du
02/11 : avec `-e ENCRYPTION_KEY=$(openssl rand -hex 32)` en plus, 503 et
« HealthLog refuses to serve: encryption key does not match » dans
`docker logs`. Ranger :

```bash
docker stop drill-healthlog-app drill-healthlog-db && docker network rm drill-healthlog
sudo rm -rf /root/restore-drill/healthlog
```

## Vérification

- Moniteur « Healthcheck HealthLog » UP ; connexion à `sante.sylvain.cloud`,
  les mesures récentes sont là.
- `curl -sI https://sante.sylvain.cloud/api/withings/webhook/0` : `401`.
- Se peser hors des minutes :00 à :05 : la pesée apparaît en quelques
  secondes (webhook), pas à l'heure suivante.
- Après une restauration : l'appli sert (`/api/health` en 200, pas de
  « encryption key does not match » dans `docker logs healthlog`) : son
  contrôle de clé au démarrage a ouvert la ligne témoin, la clé est la
  bonne. Puis Intégrations → Withings « Connecté » et « Tester la
  connexion » (le jeton chiffré se lit).

## Prévention

- Jamais de rotation de `backup_passphrase` sans figer d'abord les clés
  HealthLog (et celles des autres rôles qui en dérivent : Dawarich, TREK,
  MediaManager, Karakeep, Papra, Homebox).
- Renovate ne fusionne jamais une montée de HealthLog : relire les notes de
  version et, si le chemin du webhook change, les sources listées dans
  `tofu/pangolin_config/path_bypass_images.json`.
