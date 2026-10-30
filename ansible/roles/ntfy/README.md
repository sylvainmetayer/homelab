# ntfy

Serveur de notifications push du homelab (`ntfy.sylvain.cloud`, VM docker). Les producteurs (Uptime Kuma, scripts des hôtes, workflows GitHub) publient chacun dans leur topic avec leur jeton (`ntfy_publishers`, `defaults/main.yml`) ; l'utilisateur `sylvain` lit tous les topics depuis l'appli des téléphones. `auth-default-access` est `deny-all`. Les routes ouvertes sans SSO dans Pangolin (`local.ntfy_publish_topics`, `tofu/pangolin_config/website_ntfy.tf`) suivent la même liste de topics (test `ntfy_topics_match_the_role`).

## Retirer un topic : d'abord les téléphones

L'appli Android ouvre **une seule connexion pour tous ses topics** du serveur (`/uptime-kuma,scripts,github/ws`, ou `/…/json` en flux JSON). Si `sylvain` n'a plus le droit de lire un seul de ces topics, ntfy refuse la connexion entière (403) : **plus aucune notification n'arrive sur ce téléphone**, sans erreur visible ni alerte côté serveur. L'appli iOS ne garde pas de connexion : elle interroge chaque topic à part (`/<topic>/json?poll=1`) sur un `poll_request` relayé par ntfy.sh, seul le topic retiré y échoue.

C'est arrivé le 29/10/2026 : le retrait du topic `beszel` (#978), encore abonné dans l'appli, a coupé les notifications de 18:24 au lendemain 07:27. Telegram les recevait toujours.

Ordre à suivre (le merge sur `main` déploie le rôle aussitôt : l'étape 1 se fait avant le merge, pas seulement avant le commit) :

1. Désabonner le topic dans l'appli ntfy de **chaque** téléphone.
2. Ensuite seulement, merger le retrait. Il touche, comme celui de `beszel` (#978) : `ntfy_publishers` et `local.ntfy_publish_topics` (comparés par le test `ntfy_topics_match_the_role`), les deux listes de chemins ntfy de `tofu/pangolin_config/tests/invariants.tftest.hcl`, le faux jeton de `ansible/molecule/_shared/vars/fake_secrets.yml`, `docs/apps.md`, `docs/acces-mobile.md` et la section ntfy de `docs/runbooks/rotation-des-secrets.md` ; puis, à part, la clé SOPS `ntfy_<nom>_token` et son entrée de `secrets-rotation.yaml` (pour `github`, aussi l'environnement `ntfy-github` de `tofu/github`).
3. Supprimer l'ACCEPT du topic, encore actif dans Pangolin : sinon l'audit `terraform_data.rule_inventory` (`rules.tf`) arrête chaque plan complet de `pangolin_config`. Une fois : `tofu apply -target='pangolin_resource_rule.path_bypass["ntfy /<topic>"]'`, puis un plan normal.
4. Vérifier que les téléphones Android sont reconnectés : `docker logs --since 2m ntfy | grep "Server stats"` doit montrer `subscribers` égal au nombre de topics abonnés par les téléphones Android (un par topic et par téléphone ; l'interface web ouverte en ajoute, un iPhone n'en compte aucun), jamais 0 avec un Android abonné.
