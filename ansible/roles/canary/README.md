# Rôle `canary` (jetons pièges)

Faux identifiants posés sur les hôtes de `00-setup.yaml` (docker, pi, pangolin, flip, newt-lxc) : personne n'a de raison légitime d'y toucher, donc tout usage alerte. Quand l'un sonne : [`docs/runbooks/jeton-piege.md`](../../../docs/runbooks/jeton-piege.md).

Déployé par `00-setup.yaml` seulement (tags `canary,security`), que la CI ne lance jamais : à la main, `ansible-playbook 00-setup.yaml --tags canary` (newt-lxc compris : il est dans le groupe du play).

## Deux familles

| Piège | Où | Ce qui sonne | Alerte |
|---|---|---|---|
| Clé AWS Canarytokens | `~sylvain/.aws/credentials` | un appel à l'API AWS avec la clé, d'où qu'il vienne | Thinkst : courriel + webhook ntfy (topic `canary`) |
| Clé AWS Canarytokens | `/opt/s3-backup/.env` | idem, jeton distinct (on sait quel fichier a fuité) | idem |
| Fichier piège | `~sylvain/acces-secours.txt` | toute ouverture (lecture), suppression ou renommage | `canary-watch.service` → ntfy topic `scripts` |
| Compte SSH fictif `borg-restore` | cité dans le fichier piège, absent de l'hôte | toute tentative de connexion sous ce nom (`Invalid user borg-restore from …` dans le journal de `ssh.service`) | idem |

Les clés Canarytokens sonnent même hors de l'hôte (une copie exfiltrée, une sauvegarde volée) ; les pièges maison sonnent sur l'hôte même, sans tiers.

## Jetons Canarytokens.org

Le rôle ne fait que **déployer** des jetons que Sylvain crée lui-même sur <https://canarytokens.org> (il y faut son adresse mail). Leurs valeurs sont des secrets : clé SOPS facultative `canarytokens` de `secrets/ansible.sops.yaml`, un dictionnaire par `inventory_hostname`, chaque partie facultative :

```yaml
canarytokens:
  docker:
    aws: {access_key_id: AKIA…, secret_access_key: …}   # ~/.aws/credentials
    env: {access_key_id: AKIA…, secret_access_key: …}   # /opt/s3-backup/.env
  pi:
    aws: {…}
```

Un hôte absent, ou une partie absente : rien n'est posé, et rien n'est retiré (un fichier déjà posé reste, à effacer à la main).

### Créer les jetons

Pour chaque hôte et chaque fichier voulu (jusqu'à dix jetons : `aws` et `env` × docker, pi, pangolin, flip, newt-lxc) :

1. Sur canarytokens.org, type **AWS keys**.
2. Courriel : l'adresse de Sylvain. Webhook : l'URL ntfy ci-dessous.
3. Mémo (il revient dans chaque alerte, c'est lui qui dit quel fichier a fuité) : `homelab <hôte> ~/.aws/credentials` ou `homelab <hôte> /opt/s3-backup/.env`.
4. Relever `aws_access_key_id` et `aws_secret_access_key` du fichier proposé, et garder le lien de gestion (*Manage this Canarytoken*) dans KeePass, une entrée par jeton : c'est là qu'on le désactive.
5. `sops set` dans `secrets/ansible.sops.yaml` (commit dans le sous-module, puis son bump ici en PR), entrée `canarytokens` dans `secrets/secrets-rotation.yaml` (`kind: application`, `how: docs/runbooks/rotation-des-secrets.md#jetons-pièges`).
6. `ansible-playbook 00-setup.yaml --tags canary`.

### Webhook vers ntfy

Topic **`canary`**, producteur à part du rôle `ntfy` (`ntfy_publishers`) avec son propre jeton en écriture seule, clé SOPS `ntfy_canary_token` : c'est un tiers (Thinkst) qui le détient, jamais le jeton `scripts` des hôtes. Chemin `/canary` ouvert sans SSO dans Pangolin (`local.ntfy_publish_topics`), de tout pays comme chaque ACCEPT de chemin.

Canarytokens poste un JSON (`memo`, `src_ip`, `time`, `manage_url`, `token_type`, `channel`, `additional_data`) et ne sait pas poser d'en-tête : le jeton passe dans le paramètre `auth` de ntfy (`Bearer <jeton>` en base64 URL sans `=`), et le gabarit de ntfy (`tpl=1`) fait le titre et le message à partir du JSON :

```bash
TOKEN=tk_…   # ntfy_canary_token
AUTH=$(printf 'Bearer %s' "$TOKEN" | base64 -w0 | tr -d '=' | tr '+/' '-_')
TITLE='Jeton piège : {{.memo}}'
MSG='{{.token_type}} utilisé depuis {{.src_ip}} le {{.time}}. Gérer : {{.manage_url}}'
python3 -c 'import sys, urllib.parse as u; print("https://ntfy.sylvain.cloud/canary?" + u.urlencode({"auth": sys.argv[1], "tpl": "1", "t": sys.argv[2], "m": sys.argv[3], "p": "5", "ta": "rotating_light"}))' "$AUTH" "$TITLE" "$MSG"
```

L'URL imprimée est celle à coller dans le champ *Webhook* (elle porte le jeton : la même pour tous les jetons, ne pas la publier). Un champ absent du JSON s'affiche `<no value>` : sans gâcher l'alerte, il suffit de retirer `tpl`, `t` et `m` pour recevoir le JSON brut.

### Tester

- Le webhook : Canarytokens envoie un message de test à l'enregistrement ; il doit arriver sur le topic `canary` de l'appli ntfy (s'abonner au topic d'abord). Ou, sans Canarytokens : `curl -d '{"memo":"test","src_ip":"1.2.3.4","time":"maintenant","manage_url":"-","token_type":"aws_keys"}' "<URL du webhook>"`.
- Un jeton, de bout en bout : depuis le poste, jamais depuis l'hôte, `docker run --rm -e AWS_ACCESS_KEY_ID=… -e AWS_SECRET_ACCESS_KEY=… amazon/aws-cli sts get-caller-identity` (échoue : c'est attendu). Le courriel et le message ntfy arrivent en quelques minutes (jusqu'à une demi-heure : Thinkst lit CloudTrail). Prévenir que ce test-là sonne, puis rien à faire.

## Pièges maison

`canary-watch.service` (root, `ProtectSystem=strict`, relancé sans fin) lance `/usr/local/lib/canary/canary-watch`, deux veilles en parallèle :

- `inotifywait` sur le **dossier** du fichier piège (la veille survit à sa suppression), filtré sur son nom : `OPEN`, `DELETE`, `MOVED_FROM` ;
- `journalctl --follow` sur `ssh.service` (les processus `sshd-session`, `sshd-auth` y vivent), à l'affût de `Invalid user borg-restore from`.

Chaque alerte va au journal (`journalctl -t canary`, priorité `alert`, donc aussi dans VictoriaLogs) puis sur ntfy, topic `scripts`, jeton `ntfy_scripts_token` (`/usr/local/lib/canary/canary.env`, 0600 root, lu par curl sur un descripteur, jamais sur une ligne de commande), priorité 5 (urgente). Au plus une alerte ntfy par piège et par minute (`canary_alert_interval`) ; le journal les a toutes. Sans `ntfy_scripts_token`, le journal seulement.

Le compte fictif n'existe pas : aucun compte, aucun mot de passe, aucune règle sshd en plus. sshd refuse comme pour n'importe quel nom inconnu, fail2ban compte la tentative, ssh-audit et devsec ne voient rien de changé. Le nom est hors des dictionnaires des robots (Pangolin a son 22 ouvert à Internet) ; si un robot finit par l'essayer, changer `canary_honey_user` (et effacer le fichier piège pour qu'il soit recréé avec le nouveau nom).

Le fichier piège n'est posé qu'une fois, avec un mot de passe et une phrase de passe tirés au hasard (rien dans le dépôt), et **jamais relu par Ansible** : un `stat` ordinaire l'ouvrirait (type MIME par `file`, attributs par `lsattr`, somme de contrôle), un `template` aussi, même en `force: false`. Le rôle fait un `stat` sans rien de tout ça, puis le `template` seulement si le fichier manque. Changer son contenu : l'effacer (ce qui sonne : prévenir), puis relancer le rôle.

## Fausses alertes écartées

- **Ansible** : le stat aveugle ci-dessus ; le scénario Molecule `canary` passe le converge et l'idempotence guetteur en marche et vérifie qu'aucune alerte n'est partie. Les fichiers Canarytokens, eux, sont relus à chaque passage (somme de contrôle) : sans effet, ils ne sonnent qu'à l'usage de la clé.
- **Borgmatic** : ses `source_directories` sont les dossiers des applis, jamais `/home/sylvain` ni `/opt/s3-backup`.
- **Vector** (`log_agent`) : journald et Docker seulement, aucun fichier. **Beszel** : `/proc`, `/sys`, les disques.
- **vzdump** (VM docker, LXC newt) : en mode `snapshot`, il lit un instantané LVM monté à part (autres inodes : inotify ne voit rien) ; la VM est sauvegardée par blocs. Vérifier, le lendemain du premier déploiement, qu'aucune alerte n'est tombée vers 21:00. Un LXC repassé en mode `suspend` (rsync du système de fichiers vivant) sonnerait chaque soir.
- **Sauvegardes Hetzner** (Pangolin, flip) : par blocs.
- `ls`, la complétion du shell, `updatedb` ne font que lister. Sonnent : `cat`, `grep -r` dans le dossier personnel, un explorateur qui prévisualise (VS Code Remote qui indexe `~`), une copie du dossier personnel. Ce sont justement les gestes d'un intrus ; si c'était Sylvain, l'alerte se classe.

## Retirer

`canary_enabled: false` arrête et retire le guetteur (service, script, jeton). Les leurres restent : les effacer à la main ensuite (le guetteur arrêté, `~/acces-secours.txt` ne sonne plus), avec `~/.aws/credentials` et `/opt/s3-backup/` ; désactiver les jetons sur canarytokens.org (lien de gestion) et retirer la clé `canarytokens`.
