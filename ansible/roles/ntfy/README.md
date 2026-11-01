# ntfy

Serveur de notifications push du homelab (`ntfy.sylvain.cloud`, VM docker). Les producteurs (Uptime Kuma, scripts des hôtes, workflows GitHub, webhook Canarytokens.org du rôle `canary`) publient chacun dans leur topic avec leur jeton (`ntfy_publishers`, `defaults/main.yml`) ; l'utilisateur `sylvain` lit tous les topics depuis l'appli des téléphones. `auth-default-access` est `deny-all`. Les routes ouvertes sans SSO dans Pangolin (`local.ntfy_publish_topics`, `tofu/pangolin_config/website_ntfy.tf`) suivent la même liste de topics (test `ntfy_topics_match_the_role`).

## Droits

Déclarés dans `templates/server.yml.j2` (`auth-users`, `auth-access`, `auth-tokens`), recréés par ntfy à chaque démarrage ; un compte ou un jeton qui n'y figure plus est supprimé :

- `sylvain` (appli des téléphones, interface web) : `sylvain:*:ro` (lecture de tous les topics, existants ou retirés) plus `rw` sur chaque topic de `ntfy_publishers` (le droit le plus précis l'emporte sur le joker). Mot de passe : clé SOPS `ntfy_sylvain_password`, lue par personne (c'est celui saisi dans l'appli) ; le rôle ne déploie que son hash bcrypt `ntfy_sylvain_password_hash`.
- Chaque producteur : `wo` sur son seul topic, un jeton (`tk_…`) ; un jeton vide retire le producteur.

## Retirer un topic

L'appli Android ouvre **une seule connexion pour tous ses topics** du serveur (`/uptime-kuma,scripts,github/ws`, ou `/…/json` en flux JSON) : si `sylvain` ne peut plus lire un seul de ces topics, ntfy refuse la connexion entière (403) et **plus aucune notification n'arrive sur ce téléphone**, sans erreur visible ni alerte côté serveur (l'appli iOS interroge chaque topic à part : seul le topic retiré y échoue). C'est arrivé le 29/10/2026 : le retrait du topic `beszel` (#978), encore abonné dans l'appli, a coupé les notifications de 18:24 au lendemain 07:27 ; Telegram les recevait toujours.

Depuis, `sylvain` lit tous les topics (« Droits ») : un topic retiré reste lisible (vide), la connexion n'est plus refusée. **Ne pas retirer le joker en lecture.** L'« Alerte : aucun abonné » attrape une coupure de ce genre quand elle laisse ntfy sans aucun abonné pendant 8 h : elle ne voit rien si un autre téléphone Android ou l'interface web reste abonné.

Ordre à suivre :

1. Désabonner le topic dans l'appli ntfy de chaque téléphone (ménage : il ne coupe plus rien).
2. Merger le retrait. Il touche, comme celui de `beszel` (#978) : `ntfy_publishers` et `local.ntfy_publish_topics` (comparés par le test `ntfy_topics_match_the_role`), les deux listes de chemins ntfy de `tofu/pangolin_config/tests/invariants.tftest.hcl`, le faux jeton de `ansible/molecule/_shared/vars/fake_secrets.yml`, `docs/apps.md`, `docs/acces-mobile.md` et la section ntfy de `docs/runbooks/rotation-des-secrets.md` ; puis, à part, la clé SOPS `ntfy_<nom>_token` et son entrée de `secrets/secrets-rotation.yaml` (commit dans le sous-module `secrets/`, puis son bump ; pour `github`, aussi l'environnement `ntfy-github` de `tofu/github`).
3. Supprimer l'ACCEPT du topic, encore actif dans Pangolin : sinon l'audit `terraform_data.rule_inventory` (`rules.tf`) arrête chaque plan complet de `pangolin_config`. Une fois : `tofu apply -target='pangolin_resource_rule.path_bypass["ntfy /<topic>"]'`, puis un plan normal.
4. Vérifier que les téléphones Android sont reconnectés : `docker logs --since 2m ntfy | grep "Server stats"` doit montrer `subscribers` égal au nombre de topics abonnés par les téléphones Android (un par topic et par téléphone ; l'interface web ouverte en ajoute, un iPhone n'en compte aucun), jamais 0 avec un Android abonné.

## Alerte : aucun abonné

Le healthcheck de ntfy reste vert quand les téléphones ne reçoivent plus rien (29/10/2026). ntfy écrit chaque minute une ligne `INFO Server stats (…, subscribers=N, …)` ; toutes les 10 minutes (`ntfy_subscribers_check_schedule`), le timer `ntfy-subscribers-check` de la VM docker lance `files/ntfy-subscribers-check.sh` (installé en `/usr/local/libexec/ntfy-subscribers-check.sh`), qui relit les 8 dernières heures de `docker logs ntfy` (`ntfy_subscribers_check_window_minutes: 480`) et pousse **up** si un relevé compte au moins un abonné, **down** sinon (zéro partout, aucune ligne : ntfy arrêté, `docker logs` en échec). Sur un down, l'unité sort en échec (`systemctl --failed`).

Le relevé `Server stats` est au niveau INFO : il faut `log-level: info` (ou plus bavard) dans `templates/server.yml.j2`, sinon plus aucune ligne, et l'alerte tombe en permanence.

Pourquoi 8 h (et pas 30 min) : un téléphone éteint, en mode avion ou sans réseau une nuit ne doit pas alerter ; 8 h sans aucun abonné, c'est un vrai souci (abonnement refusé, appli coupée).

Les pièces :

- moniteur push « ntfy : abonnés » (`tofu/pangolin_config/cron_ntfy_subscribers.tf`) : un down passe d'abord en PENDING, l'alerte tombe au second, un peu plus de 8 h après le départ du dernier abonné, aussi sur Telegram (ntfy ne joindrait justement plus personne) ;
- URL push : sortie `uptime_cron_ntfy_subscribers_url` du state de `pangolin_config`, lue par `docker.yml` dans `ntfy_subscribers_check_push_url` ; vide, le script tourne sans rien pousser ;
- le script tourne sous `ntfy_subscribers_check_user` (groupe `docker`), jamais root.

Vérifier :

```bash
journalctl -u ntfy-subscribers-check            # « up: jusqu'à N abonné(s) sur 480 min » ou « down: … »
docker logs --since 2m ntfy | grep "Server stats"   # subscribers=N en ce moment
```
