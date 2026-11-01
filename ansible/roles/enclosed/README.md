# enclosed

[Enclosed](https://github.com/CorentinTh/enclosed) sur **https://pwpush.sylvain.cloud** :
des notes chiffrées de bout en bout, supprimées à la première lecture et
expirées au bout de quelques jours. Elles servent à remettre un jeton ou une
clé renouvelés (jeton d'accès Pangolin, clé d'API Immich...) sous forme d'un
lien, sans que la valeur ne s'affiche nulle part ailleurs. VM docker,
`dc@enclosed`, un conteneur `enclosed` (image `-rootless`, système de fichiers
en lecture seule, aucune capacité) sur `newt` et sur le réseau interne
`enclosed-cli`.

Le chiffrement se fait chez le client (navigateur ou `enclosed-share`), la clé
ne voyage que dans le fragment du lien (`#dar:<clé>`), jamais envoyé au
serveur : Enclosed ne stocke que du chiffré.

## Qui peut quoi

- **Lire** une note : tout le monde, de n'importe quel pays, sans SSO, par les
  seuls chemins de lecture (`local.enclosed_read_paths`,
  `tofu/pangolin_config/website_enclosed.tf`) : la page `/<id>` (un ULID,
  qui commence par `0`), `/assets/*`, `GET /api/notes/<id>` et
  `/api/notes/<id>/exists`. Sans la clé du fragment, la note n'est que du
  chiffré ; une note « supprimée à la lecture » l'est au premier
  `GET /api/notes/<id>`.
- **Créer** une note : derrière le SSO de Pangolin (rôle `enclosed`, sans
  membre : administrateurs Pangolin seulement). Le formulaire `/` et
  `POST /api/notes` ne sont dans aucune ouverture : Pangolin compare les
  chemins, pas les méthodes, et ces motifs `0*` ne prennent qu'un segment,
  donc jamais `/api/notes` lui-même (le détail est dans
  `website_enclosed.tf`). Pas de compte Enclosed
  (`PUBLIC_IS_AUTHENTICATION_REQUIRED=false`) : il ne protégerait rien de plus,
  une note publique se lisant de toute façon sans compte.
- Depuis la VM docker, `enclosed-share` crée une note sans passer par
  Pangolin (ci-dessous).

Les chemins ouverts ont été relus sur la version 1.16.1 :
`tofu/pangolin_config/path_bypass_images.json` garde cette version et ce qu'il
faut relire. Renovate ne fusionne jamais seul une montée de cette image ; il
monte `@enclosed/lib` (`files/cli/package.json`) dans la même PR (groupe
`enclosed`).

## Valeurs par défaut

| | Formulaire web | `enclosed-share` |
|---|---|---|
| Suppression à la première lecture | cochée | oui (`--keep` pour non) |
| Expiration | 1 jour (Enclosed n'accepte qu'1 h, 1 j, 1 sem. ou 1 mois ici) | 3 jours (`--ttl`) |
| Plafond | 30 jours, codé en dur dans le serveur ; « sans expiration » refusé (`PUBLIC_IS_SETTING_NO_EXPIRATION_ALLOWED=false`) | idem |

Taille d'une note chiffrée : 5 Mio au plus (`enclosed_max_payload_bytes`).
Les notes expirées sont purgées chaque heure par le serveur.

## enclosed-share

Sur la VM docker, en tant que `sylvain` (groupe `docker`) :

```bash
printf %s "$JETON" | enclosed-share            # 1 lecture, 3 jours
enclosed-share --ttl 3600 < cle.txt            # 1 lecture, 1 heure
enclosed-share --keep --ttl 86400 < cle.txt    # lisible 1 jour, sans limite de lectures
```

Depuis le poste, sans que le secret ne touche le disque ni la ligne de
commande distante (depuis `ansible/`, comme `mise run ssh`) :

```bash
ip=$(ansible-inventory --host docker | jq -er '.ansible_host')
printf %s "$JETON" | ssh -i ~/.ssh/keepassxc.pub -o UserKnownHostsFile=known_hosts \
  -o StrictHostKeyChecking=yes "sylvain@$ip" enclosed-share
```

Il lit le secret sur l'entrée standard (un seul saut de ligne final retiré,
celui d'un `echo`) et n'écrit sur la sortie standard que le lien
`https://pwpush.sylvain.cloud/<id>#dar:<clé>`, à transmettre tel quel. Code
de sortie 1 si la note n'a pas été créée (entrée vide, conteneur arrêté,
refus du serveur), 2 pour une option invalide.

Fonctionnement (`templates/enclosed-share.j2`) :

1. Au premier appel, puis à chaque changement de `package-lock.json`, `npm ci`
   installe `@enclosed/lib` (la bibliothèque officielle, même version que le
   serveur, dépendances verrouillées, sans scripts d'installation ni binaires
   optionnels) dans `/opt/apps/enclosed/cli/node_modules`, dans un conteneur
   jetable de l'image d'Enclosed. Ce conteneur-là voit le registre npm, aucun
   secret.
2. `share.mjs` tourne dans un second conteneur jetable de la même image,
   **sur le seul réseau interne `enclosed-cli`** : pas de route vers Internet,
   seul le serveur `enclosed` y répond. Il chiffre, envoie le chiffré à
   `http://enclosed:8787/api/notes` et écrit le lien. `--log-driver none` :
   ni le lien ni rien d'autre n'arrive dans les journaux Docker ni chez
   Vector.

Pas de rôle Pangolin ni de jeton à gérer : le script ne passe pas par
Pangolin. L'image est celle du conteneur qui tourne (`docker inspect`), donc
toujours celle de `compose.yaml`.

## Pas de sauvegarde

Exprès : des secrets à usage unique, valables quelques jours, n'ont rien à
faire dans une archive borg gardée des mois. Ni configuration borgmatic, ni
moniteur « Backup », ni entrée dans `.github/restore-test/apps.json`. Les
notes vivent dans le volume nommé `enclosed_data` (`/app/.data`), perdu avec
la VM : une note perdue se recrée.

## Ressources

`mem_limit: 256m`, pas encore mesuré (serveur Node sans état en mémoire) : à
recaler sur `memory.peak` (rapport `mem_report`) après quelques semaines,
selon `docs/conventions/resource-limits.md`.

## Déploiement

`tofu/pangolin_config` d'abord (ressource, rôle SSO, chemins ouverts,
moniteur), puis `ansible-playbook docker.yml --tags enclosed`, puis
`--tags homepage` pour le lien.
