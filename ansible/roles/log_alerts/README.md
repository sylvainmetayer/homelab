# Rôle `log_alerts`

Alertes sur les journaux de VictoriaLogs (étude q-logalert du 07/11/2026). Sur la VM docker (`docker.yml`, tag `log_alerts`), `log-alerts.timer` lance toutes les 5 minutes `files/log_alerts.py` (bibliothèque standard seule, compte éphémère `DynamicUser`, état dans `/var/lib/log-alerts/state.json`). Même chaîne que `ci_key_audit` : requêtes par `127.0.0.1:9428` avec le compte Basic `sylvain` (sops `victoria_logs_ui_password`, chemin `/select/logsql/query` seul), alertes ntfy (topic `scripts`, sops `ntfy_scripts_token`), battement `up` par `uptime-push`. Aucun conteneur de plus (pas de vmalert) et aucune clé SOPS nouvelle.

## Règles (`log_alerts_rules`)

Chaque règle est une requête LogsQL finissant par `stats by (...) count() n`, jugée sur une fenêtre glissante.

| Règle | Requête (extrait) | Fenêtre | Seuil | ntfy | Répétition |
|---|---|---|---|---|---|
| `traefik-5xx` | `source:traefik status:in(502,503,504)`, par `router` | 5 min | >= 10 | 3 | 1 h par routeur |
| `oom-kill` | `OOMKilled`, `exited with code 137`, `status=9/KILL` ou la ligne du noyau `out of memory: Killed process` (seule trace sous `compose up -d`, Pangolin ; `unit` vide), hors `session.scope` et `dc@homepage.service`, par `host, unit` | 15 min | >= 1 | 4 | 1 h |
| `oom-kill-homepage` | idem pour `dc@homepage.service` (sa limite mémoire est déjà un sujet connu : 37 kills en 10 jours) | 1 h | >= 3 | 3 | 6 h |
| `borgmatic-absent` | `unit:"borgmatic.service"`, par `host` ; alerte pour chaque hôte de `log_alerts_borgmatic_hosts` (docker, pangolin, pi, flip, nas) sans aucune ligne | 26 h | absence | 5 | 24 h |
| `borgmatic-failed` | `_msg:"borgmatic.service: Failed with result"`, par `host` (la ligne vient de systemd : son `unit` vaut `init.scope`, le nom de l'unité n'est que dans le message) | 26 h | >= 1 | 5 | 24 h |
| `unit-failed` | `_msg:"Failed with result"`, nom de l'unité extrait du message, par `host, u`, hors borgmatic (règle ci-dessus), `log-alerts.service` (push qui expire vers 03:15, son moniteur le couvre), `tmp.mount` (le LXC l'échoue toutes les 5 min), `dc@*.service` (échec à chaque redémarrage de déploiement), le NAS (unités UGOS bruyantes) et `session.scope` | 15 min | >= 1 | 4 | 6 h par unité |

- `session.scope` est exclu : les commandes tapées en SSH (une requête comme celle-ci) citent les mots cherchés.
- `borgmatic-absent` est un filet : le moniteur push de chaque sauvegarde (`uptime_push`) reste la première alerte. Un nouvel hôte sauvegardé s'ajoute à `log_alerts_borgmatic_hosts`.
- Seuils mesurés sur 10 jours seulement (rétention récente de VictoriaLogs) : à rejouer dans un mois. Sur ces 10 jours, `traefik-5xx` aurait sonné 6 fois (fenêtres fixes de 5 min), `oom-kill` une dizaine de fois, `oom-kill-homepage` 7 fois, les deux borgmatic jamais. Rejeu du 11/11 sur les 14 jours de journaux : `oom-kill` avec la ligne du noyau en gagne 10 (9 au 09-10/11 sur docker, 1 sur pangolin), `unit-failed` aurait sonné 10 fois (6 unités ; 5 fois `log-alerts.service` lui-même, exclu depuis : son push expire vers 03:15, 02:16 UTC), `borgmatic-failed` jamais.
- Une alerte ne se répète qu'après `repeat_seconds`, par règle et par groupe (état local). Un message ntfy par règle et par passage, 20 lignes au plus.

## Moniteur « Alertes sur les journaux »

`tofu/pangolin_config/cron_log_alerts.tf`, sortie `uptime_cron_log_alerts_url` lue par `docker.yml` dans l'entrée du rôle. Intervalle de 15 minutes (trois périodes du timer, déduit par `tofu test` de `log_alerts_schedule`), sans `max_retries`.

| Cas | Effet |
|---|---|
| Toutes les règles jugées, alertes livrées | `up` avec le résumé |
| VictoriaLogs injoignable, réponse illisible, ntfy refuse | unité en échec, raison au journal (`journalctl -u log-alerts`), **aucun push** : DOWN à l'expiration. Une alerte non livrée n'est pas mémorisée : elle repart au passage suivant ; une règle qui plante après des alertes parties (réponse inattendue) n'empêche pas de sauver celles-ci, elles ne repartent pas |
| URL push vide (Tofu pas appliqué) | avertissement au déploiement, alertes ntfy sans battement |

Le moniteur ne dit donc que la cécité du contrôle : les alertes elles-mêmes passent par ntfy.

## Ajouter une règle

Une entrée de `log_alerts_rules` (`name` unique, `title`, `priority`, `query`, `window_seconds`, `threshold` ou `expect_hosts`, `repeat_seconds`). Valider la requête sur la VM (`docker exec victoria-logs-auth wget -qO- --post-data='query=...&start=1d' http://victoria-logs:9428/select/logsql/query`) avant de la figer. Vient ensuite, selon l'étude : échecs SSH sur les hôtes non exposés, boucles de redémarrage (après avoir masqué `serial-getty@ttyS0` sur la VM docker).

Molecule : scénario `log_alerts` (faux VictoriaLogs, ntfy et Uptime Kuma sur `127.0.0.1:18084`) : seuil, dédup, absence, cécité, et `files/test_log_alerts.py` (état sauvé quand une règle plante après une alerte partie).
