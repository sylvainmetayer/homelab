# CrowdSec sur Pangolin

CrowdSec protège toutes les routes HTTPS publiques de Pangolin (rôle
`pangolin`, `ansible/pangolin.yaml`). Trois morceaux :

- **Journal d'accès de Traefik** en JSON, `/opt/pangolin/config/traefik/logs/access.log`
  (en-têtes : User-Agent seul), tourné chaque jour par logrotate
  (`/etc/logrotate.d/traefik-access`, 7 jours, SIGUSR1 à Traefik). Exclu de
  borgmatic.
- **Conteneur `crowdsec`** (agent + LAPI + AppSec) dans la pile
  `pangolin.service`. Il lit ce journal, détecte (collections
  `crowdsecurity/traefik`, `http-cve`, `base-http-scenarios`) et tire la
  liste de blocage communautaire (CAPI). Pas de console, pas de sshd
  (fail2ban s'en charge). Données sous `/opt/pangolin/crowdsec`, jamais
  sauvegardées : la base locale est jetable, le hub et la CAPI reviennent au
  démarrage.
- **Bouncer** : plugin Traefik `maxlerebourg/crowdsec-bouncer-traefik-plugin`,
  middleware `crowdsec@file` sur l'entrypoint `websecure` (tableau de bord,
  API et websocket de Pangolin compris, avant Badger). Le port 80 (défi ACME,
  redirections) n'en a pas. Mode `stream` : décisions tirées toutes les 15 s,
  aucune requête n'attend la LAPI. Réponse d'une IP bannie : 403 vide.

Ce qui n'est **jamais** détecté ni bloqué : `home_ip` (secrets SOPS, la même
clé que les règles « home IP » de `tofu/pangolin_config`), l'IP publique de
Pangolin (sortie de la passerelle `vpn-flip`, appels de l'hôte à lui-même),
les plages privées (flip par le NAT, conteneurs Docker, agent Beszel) et
`pangolin_crowdsec_whitelist_extra` (`host_vars/pangolin`). Deux mécanismes,
les mêmes sources : la liste blanche s02 `homelab/whitelist` (détection) et
`clientTrustedIPs` du bouncer, sans laquelle une IP de la maison présente
dans la liste communautaire serait bloquée quand même.

L'IP vue est celle de la connexion TCP (DNAT de Docker devant gerbil) : ni
Traefik ni le bouncer ne croient un `X-Forwarded-For` reçu.

**AppSec (WAF) en détection seule** : les règles de `appsec-virtual-patching`
et `appsec-generic-rules` sont chargées *hors bande*
(`homelab/appsec-alert-only`) : le bouncer reçoit toujours « 200 », une
correspondance donne une alerte `homelab/appsec-alert-only` sans décision.
`pangolin_crowdsec_appsec_enabled: false` coupe les appels AppSec seuls.

Toutes les commandes `cscli` se lancent sur Pangolin
(`ssh sylvain@pangolin.sylvain.cloud`) : `sudo docker exec crowdsec cscli …`.

## Vérifier que tout tourne

```bash
sudo docker ps --filter name=crowdsec          # (healthy)
sudo docker logs traefik 2>&1 | grep 'Plugins loaded'   # ["badger","crowdsec"]
sudo docker exec crowdsec cscli bouncers list  # traefik, « Last API pull » < 15 s
sudo docker exec crowdsec cscli metrics show acquisition appsec scenarios
sudo docker exec crowdsec cscli decisions list --origin CAPI -o json | jq length
sudo tail -n1 /opt/pangolin/config/traefik/logs/access.log | jq '{ClientHost, RequestHost, DownstreamStatus}'
```

`acquisition` : les lignes de `file:/var/log/traefik/access.log` montent et
sont toutes « parsed » ; celles de la maison sont « whitelisted ». `appsec` :
« Processed » monte, « Blocked » reste à zéro. `ClientHost` est une vraie IP
publique, jamais une 172.x (sinon l'IP réelle est perdue, voir plus bas).

## Résumé hebdomadaire sur ntfy

Chaque lundi vers 07:30 (`crowdsec-summary.timer`, rôle `pangolin`),
`/usr/local/bin/crowdsec-summary` lit `cscli alerts list --since 168h`
(alertes locales des 7 derniers jours, sans la liste communautaire) et
`cscli decisions list`, puis publie sur le topic `scripts` de ntfy : alertes
par scénario et par pays, décisions actives, et correspondances AppSec en
détection seule. Priorité basse d'habitude, **haute** dès qu'AppSec a vu
quelque chose (à regarder avec `cscli alerts list -s homelab/appsec-alert-only`)
et quand cscli ne répond pas (le service échoue aussi). Le script est sans
état. Le jeton (`ntfy_scripts_token`) est dans `/etc/crowdsec-summary/env`
(0600), jamais sur une ligne de commande.

```bash
sudo systemctl list-timers crowdsec-summary.timer
sudo /usr/local/bin/crowdsec-summary --dry-run  # le message, sans le publier
sudo systemctl start crowdsec-summary.service  # le publier maintenant
sudo journalctl -u crowdsec-summary.service -n 20
```

Sans CrowdSec (`pangolin_crowdsec_enabled: false`) ou sans jeton, le timer et
le script sont retirés.

## Décisions et alertes

```bash
sudo docker exec crowdsec cscli decisions list            # locales (scénarios, cscli)
sudo docker exec crowdsec cscli decisions list -a         # + liste communautaire
sudo docker exec crowdsec cscli decisions list --ip 203.0.113.7
sudo docker exec crowdsec cscli alerts list               # dernières alertes
sudo docker exec crowdsec cscli alerts list -s homelab/appsec-alert-only
sudo docker exec crowdsec cscli alerts inspect -d <id>    # détail, requêtes en cause
sudo docker exec crowdsec cscli metrics                   # tout
```

Bannir à la main (4 h par défaut, comme les scénarios) :

```bash
sudo docker exec crowdsec cscli decisions add --ip 203.0.113.7 --duration 24h --reason "manuel"
sudo docker exec crowdsec cscli decisions add --range 203.0.113.0/24 --duration 24h
```

## Débannir quelqu'un

```bash
sudo docker exec crowdsec cscli decisions delete --ip 203.0.113.7
```

Le bouncer lève le blocage au tirage suivant (15 s au plus). Une IP de la
liste communautaire revient au prochain tirage CAPI (2 h) : pour une IP
légitime durablement, l'ajouter à `pangolin_crowdsec_whitelist_extra`
(`host_vars/pangolin/variables.yaml`) puis
`ansible-playbook pangolin.yaml --tags pangolin`. Dépannage immédiat, non
déclaratif (perdu si `/opt/pangolin/crowdsec` est effacé) :

```bash
sudo docker exec crowdsec cscli allowlists create depannage -d "levée manuelle"
sudo docker exec crowdsec cscli allowlists add depannage 203.0.113.7
```

Victimes probables, toutes sur des IP de cloud partagées que la liste
communautaire peut contenir : le moniteur Uptime Kuma (PikaPods, IP qui peut
changer), un runner GitHub (enregistrement OLM sur `pangolin.sylvain.cloud` :
`deploy-docker-app` échoue), les fonctions Supabase du tournoi Linkx qui
appellent Promptoramix. Rien n'alerte : symptôme, un 403 vide, et
`cscli decisions list -a --ip <ip>` la montre.

## Tester un bannissement

Depuis la maison, rien ne peut être banni (`home_ip` est de confiance) : le
test se fait depuis un téléphone **en données mobiles** (Wi-Fi coupé), qui
n'a ni SSH ni rien d'autre en jeu.

1. Sur le téléphone, ouvrir une ressource publique, par exemple Betisier.
2. Sur Pangolin, lire son IP :
   `sudo tail -n 50 /opt/pangolin/config/traefik/logs/access.log | jq -r 'select(.RequestHost | startswith("betisier")) | .ClientHost' | sort -u`
3. `sudo docker exec crowdsec cscli decisions add --ip <IP> --duration 5m --reason test`
4. Recharger la page dans les 15 s : réponse 403 vide. Une autre ressource
   aussi, et le tableau de bord de Pangolin.
5. `sudo docker exec crowdsec cscli decisions delete --ip <IP>` : la page
   revient dans les 15 s (sinon elle revient seule après 5 min).

Détection sans bannissement, depuis le même téléphone : ouvrir **une fois**
`https://<ressource>/crowdsec-test-NtktlJHV4TfBSK3wvlhiOBnl`. Attendu : la
page de l'appli (404 de l'appli, pas 403), puis
`cscli alerts list` montre `crowdsecurity/http-generic-test` (journal
d'accès) et `crowdsecurity/appsec-generic-test` (AppSec), sans décision.
Ne pas enchaîner des chemins comme `/.env` : quelques-uns suffisent à
`crowdsecurity/http-sensitive-files`, qui bannit le téléphone pour 4 h (le
débannir comme ci-dessus).

## Retour arrière

Tout CrowdSec, sans rien perdre :

```bash
cd ansible
ansible-playbook pangolin.yaml --tags pangolin -e '{"pangolin_crowdsec_enabled": false}' --check --diff
ansible-playbook pangolin.yaml --tags pangolin -e '{"pangolin_crowdsec_enabled": false}'
```

Le plugin et le middleware quittent la configuration de Traefik (le
middleware `crowdsec@file` reste défini, inerte, pour l'entrypoint que
Traefik garde jusqu'au redémarrage de la pile), le conteneur `crowdsec`
disparaît (`--remove-orphans`), `/opt/pangolin/crowdsec` reste. La pile
redémarre (environ une minute de coupure, comme tout changement du compose).
Le journal d'accès continue. Ensuite, **dans une PR**,
`pangolin_crowdsec_enabled: false` dans `ansible/host_vars/pangolin/variables.yaml` :
sinon le prochain déploiement du rôle `pangolin` par la CI le réactive.
Réactiver : retirer la ligne, même commande sans `-e`.

AppSec seul : `pangolin_crowdsec_appsec_enabled: false`, même procédure ; le
bouncer et la détection sur le journal restent.

Urgence sans Ansible : `sudo docker stop crowdsec`. Le bouncer laisse alors
tout passer (`updateMaxFailure: -1`, AppSec injoignable), sauf les IP déjà
bannies qu'il garde en mémoire jusqu'à l'expiration de leur décision.

## Pannes connues

- **Toutes les routes en 403** alors que CrowdSec tourne : AppSec refuse la
  clé du bouncer (401) et le plugin bloque sur toute réponse inattendue
  d'AppSec. `sudo docker logs traefik 2>&1 | grep appsecQuery` montre
  `unexpectedStatus statusCode:401`. Le bouncer est supprimé et recréé à
  chaque démarrage du conteneur avec `pangolin_crowdsec_bouncer_key`
  (`entrypoint` du compose) : `sudo docker restart crowdsec` suffit, à
  condition que `dynamic_config.yml` porte la même clé (relancer le rôle).
  Sinon : `pangolin_crowdsec_appsec_enabled: false`.
- **Toutes les routes en 404** après une montée de version du plugin (ou de
  Traefik) : un plugin qui ne se charge pas désactive tous les plugins,
  Badger compris (`docker logs traefik`, « Plugins loaded » absent ou en
  erreur). Retour arrière ci-dessus, ou revenir à la version précédente dans
  `traefik_config.yml.j2`.
- **`ClientHost` en 172.x** dans le journal : un proxy (userland-proxy de
  Docker, autre frontal) est passé devant Traefik, et tout le monde a l'IP
  du réseau Docker, de confiance : plus rien n'est bloqué. Vérifier
  `/etc/docker/daemon.json` et les ports publiés par gerbil.
- **Rotation de la clé du bouncer** : `sops set --value-stdin` de
  `pangolin_crowdsec_bouncer_key` dans `ansible/secrets.sops.yaml`, puis le
  rôle (compose et configuration dynamique changent ensemble, la pile
  redémarre et le bouncer est réenregistré).
- Passer AppSec **en blocage** : dans
  `templates/crowdsec/appsec-config.yaml.j2`, déplacer les règles de
  `outofband_rules` vers `inband_rules` (403 immédiat, puis bannissement
  par `crowdsecurity/appsec-vpatch`). Lire d'abord
  `cscli alerts list -s homelab/appsec-alert-only` sur quelques semaines :
  chaque alerte serait devenue un 403.
