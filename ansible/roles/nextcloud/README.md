
## Connexion par Pocket ID

Client `nextcloud` de `tofu/pangolin_config/pocket_id.tf` (groupe
`nextcloud`). Quand les sorties Tofu sont là, le rôle installe l'app
`user_oidc` (magasin d'applis, dernière version compatible) et pose le
fournisseur « Pocket ID » par `occ user_oidc:provider` (upsert, rejoué à
chaque passage ; secret par l'environnement du `docker exec`, `no_log`).
Liaison **par uid** : `--mapping-uid=preferred_username --unique-uid=0`, et
`soft_auto_provision` dans `homelab.config.php` retrouve le compte local de
même uid. Un uid ne se renomme pas : c'est le nom d'utilisateur Pocket ID qu'on
aligne. `disable_account_creation` : un login sans compte local échoue au lieu
d'en créer un vide. Pas de synchro de groupes (`--group-provisioning=0`) : elle
retirerait les groupes locaux absents du claim, `admin` compris. Le formulaire
local reste (`allow_multiple_user_backends`, `/login?direct=1`) ; les clients
gardent leurs mots de passe d'application.

## Assistant (passerelle IA de Pangolin)

Le rôle installe `integration_openai` et `assistant` (`nextcloud_ai_apps`).
Le service se règle à la main, une fois, dans Administration →
Intelligence artificielle → OpenAI et LocalAI : `integration_openai` garde ses
services en JSON chiffré, sans commande `occ` pour les écrire.

- URL du service : `https://ia.sylvain.cloud/v1`
- Clé : la clé virtuelle `nextcloud`, depuis un worktree à jour de `main`,
  copiée sans l'afficher :

  ```bash
  mise exec -- tofu -chdir=tofu/pangolin_config output -json ai_gateway_keys | jq -r .nextcloud | wl-copy
  ```

- Point de terminaison chat activé ; modèle par défaut `claude-haiku-5-5`
  (taper le nom s'il n'est pas proposé : la liste vient de `/v1/models`).
- Rien pour les images, la voix ni la traduction audio : la passerelle ne sert
  que du texte.
