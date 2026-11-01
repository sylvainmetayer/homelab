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
[mot-de-passe-base.md](mot-de-passe-base.md)) et `-healthlog-api-token-hmac`
(`healthlog_api_token_hmac_key`, sinon tous les jetons d'API tombent).

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
grep -E '^(ENCRYPTION_KEY|API_TOKEN_HMAC_KEY)=' /root/restore/healthlog/opt/apps/healthlog/.env
```

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

## Vérification

- Moniteur « Healthcheck HealthLog » UP ; connexion à `sante.sylvain.cloud`,
  les mesures récentes sont là.
- `curl -sI https://sante.sylvain.cloud/api/withings/webhook/0` : `401`.
- Se peser hors des minutes :00 à :05 : la pesée apparaît en quelques
  secondes (webhook), pas à l'heure suivante.
- Après une restauration : Intégrations → Withings « Connecté » (les jetons
  chiffrés se lisent, donc la clé est la bonne).

## Prévention

- Jamais de rotation de `backup_passphrase` sans figer d'abord les clés
  HealthLog (et celles des autres rôles qui en dérivent : Dawarich, TREK,
  MediaManager).
- Renovate ne fusionne jamais une montée de HealthLog : relire les notes de
  version et, si le chemin du webhook change, les sources listées dans
  `tofu/pangolin_config/path_bypass_images.json`.
