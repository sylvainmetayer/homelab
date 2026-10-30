# ntfy

Serveur de notifications push du homelab (`ntfy.sylvain.cloud`, VM docker). Les producteurs (Uptime Kuma, scripts des hôtes, workflows GitHub) publient chacun dans leur topic avec leur jeton (`ntfy_publishers`, `defaults/main.yml`) ; l'utilisateur `sylvain` lit tous les topics depuis l'appli des téléphones. `auth-default-access` est `deny-all`. Les routes ouvertes sans SSO dans Pangolin (`local.ntfy_publish_topics`, `tofu/pangolin_config/website_ntfy.tf`) suivent la même liste de topics.

## Retirer un topic : d'abord les téléphones

L'appli ntfy ouvre **une seule connexion pour tous ses topics** (`/uptime-kuma,scripts,github/json`). Si `sylvain` n'a plus le droit de lire un seul de ces topics, ntfy refuse la connexion entière (403) : **plus aucune notification n'arrive sur ce téléphone**, sans erreur visible ni alerte côté serveur.

C'est arrivé le 29/10/2026 : le retrait du topic `beszel` (#978), encore abonné dans l'appli, a coupé les notifications de 18:24 au lendemain 07:27. Telegram les recevait toujours.

Ordre à suivre :

1. Désabonner le topic dans l'appli ntfy de **chaque** téléphone.
2. Ensuite seulement, le retirer de `ntfy_publishers` et de `local.ntfy_publish_topics`.
3. Vérifier que les téléphones sont reconnectés : `docker logs --since 2m ntfy | grep "Server stats"` doit montrer `subscribers` égal au nombre de topics abonnés (un par topic et par téléphone), jamais 0.
