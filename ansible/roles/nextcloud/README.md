
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
