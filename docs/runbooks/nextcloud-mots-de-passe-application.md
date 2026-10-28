# Clients Nextcloud et mots de passe d'application

Procédure, pas un incident : vérifier que chaque client (DAVx5, client de
bureau, Évolution, GNOME Online Accounts, rclone…) s'authentifie par un
**mot de passe d'application** et non par le mot de passe de connexion, et
en créer un au besoin. C'est le préalable à `token_auth_enforced` (#701) :
une fois activé, Nextcloud refuse le mot de passe de connexion hors du
navigateur, et un client resté dessus cesse de synchroniser.

L'outil : [`nextcloud-app-passwords.sh`](nextcloud-app-passwords.sh), à
lancer depuis le poste, sur le réseau local (il joint la VM docker en SSH,
clé d'hôte vérifiée contre `ansible/known_hosts`, et passe par
`sudo docker exec nextcloud occ`).

## Symptôme

- Avant d'activer `token_auth_enforced` : savoir qui est encore sur le mot
  de passe de connexion.
- Après : un client réclame le mot de passe en boucle, ou ne synchronise
  plus, alors que la connexion web marche.

## Diagnostic

```bash
docs/runbooks/nextcloud-app-passwords.sh        # audit, ne modifie rien
```

Il lit trois choses et ne fait sortir de la VM que des noms et des dates :

- les comptes (`occ user:list`) ;
- leurs mots de passe d'application (`occ user:auth-tokens:list`, type 1) :
  id, nom, dernière activité, jamais la valeur ;
- les requêtes de synchronisation des 14 jours de journaux nginx
  (`/remote.php`, `/ocs`, les API des applis) : utilisateur, jour, agent
  client. Ni IP ni URL.

Chaque agent est rangé dans une famille (DAVx5, Nextcloud Android, client de
bureau, Thunderbird, Évolution, GNOME Online Accounts, rclone, davfs2,
script Go, Outlook), puis rapproché d'un jeton par son nom :

- **OK** : un mot de passe d'application porte un nom de cette famille ;
- **à vérifier** : aucun nom ne correspond, mais un jeton a servi le jour du
  dernier passage du client (un jeton nommé d'après le poste, par exemple) ;
- **AUCUN, à migrer** : sans doute le mot de passe de connexion.

C'est une déduction : le journal ne dit pas quel secret le client a envoyé.
Un « à vérifier » se tranche dans les réglages du compte du client. Un
client absent des familles n'apparaît pas : l'ajouter à `FAMILIES` dans le
script.

## Réparation

À lancer dans un terminal à soi, jamais par un agent ni avec `!` dans
Claude Code : le mot de passe s'affiche en clair, une seule fois.

```bash
docs/runbooks/nextcloud-app-passwords.sh add sylvain "GNOME Online Accounts"
```

Le coller dans le client avec l'identifiant de connexion. Nommer le jeton
d'après le client : l'audit suivant le classe alors en « OK ».

Un jeton qui ne sert plus (poste rendu, client désinstallé) :

```bash
docs/runbooks/nextcloud-app-passwords.sh delete sylvain 4917   # id de l'audit
```

Le client qui l'utilisait est déconnecté tout de suite.

## Vérification

Relancer l'audit quelques jours plus tard : plus aucun « AUCUN », et la
dernière activité du nouveau jeton avance. Côté Nextcloud, la liste est
aussi dans Paramètres personnels → Sécurité → Appareils et sessions.

## Prévention

- Un nouveau client se connecte par le flux de connexion de Nextcloud
  (bouton « Se connecter » / QR code), qui crée lui-même un mot de passe
  d'application nommé d'après l'appareil, ou par un jeton créé ici.
- Une fois `token_auth_enforced` actif, un client mal configuré échoue tout
  de suite au lieu de garder le mot de passe de connexion.
