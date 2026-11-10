# Reconstruction de la VM docker depuis Borg (copie jetable sur Hetzner Cloud)

Cette page sert deux fois : **l'exercice** (reconstruire toute la VM docker sur
un serveur Hetzner Cloud jetable, chronomètre en main, puis le détruire) et le
**sinistre réel** (étage 4 de [perte-totale-maison.md](perte-totale-maison.md),
quand ni l'hôte Proxmox ni l'archive vzdump n'existent plus). Elle ferme deux
trous écrits : « VM jamais restaurée » ([matrice des données](../matrice-des-donnees.md))
et « hébergeur provisoire : non préparé » (perte-totale-maison, étage 2).

Statut : **joué une fois, le 09/11/2026** : 37 min de la création du serveur
aux contrôles, 15 applis restaurées et vérifiées sur les 17 dépôts Borg joués (beszel et healthlog exclus) (feuille de temps plus
bas). Les deux trous restants sont dans « Constats de l'exercice ».

**Données personnelles réelles sur le disque d'un hébergeur** (Nextcloud, photos
de lieux de Dawarich, documents de Papra, bases de toutes les applis) pendant
quelques heures. La destruction du serveur fait partie de la procédure, et se
vérifie (« Destruction »).

## Symptôme

- Exercice : rien n'est en panne ; on veut savoir si la VM se reconstruit, et en
  combien de temps.
- Sinistre : la VM docker (id 100) et son archive vzdump sont perdues ; les
  applis sont à rendre aux foyers depuis les dépôts Borg de la Storage Box.

## Isolation de la production

Une copie mal isolée casse la production (un second Newt prend son trafic ; une
appli restaurée écrit au foyer avec les vrais identifiants). Chaque point, et où
il est tenu :

| Risque | Garde | Preuve |
|---|---|---|
| Un second Newt vole le site `docker` | rôle `newt` exclu (`when: not drill_mode`) ; réseau `newt` créé sans Newt | `docker.yml`, rôle `docker_drill` |
| Pangolin, DNS | rien n'est créé : aucune ressource, aucun enregistrement. La copie n'a pas d'URL publique | aucun fichier `tofu/pangolin_config` ni `tofu/dns` touché |
| Borg écrit chez la production | sous-compte **restore-test** (lecture seule côté Storage Box) ; `borg-readonly` refuse `create`, `prune`, `compact`, `delete`…, `repo-create` jamais joué ; `borgmatic.timer` et `.service` masqués | `tofu/pangolin/storage_box.tf`, rôles `borgmatic`, `docker_drill` ; `systemctl is-enabled borgmatic.timer` donne `masked` |
| Rapports vers la production (Uptime Kuma, ntfy, VictoriaLogs, Telegram, Beszel, alertes) | `terraform_outputs = {}` (toutes les URL push, tous les clients OIDC, toutes les clés IA tombent à vide) ; rôles de rapport exclus ; `00-setup.yaml` (`ssh_login_notify`, `canary`) ne tourne pas sur le groupe `drill` | [README du rôle](../../ansible/roles/docker_drill/README.md), table par rôle |
| Jetons qui tournent à l'usage (Withings de HealthLog) | HealthLog exclu | idem |
| Courrier et IMAP avec les vrais identifiants | pare-feu Hetzner : sortie en liste blanche (DNS, NTP, 80, 443, 23), ni 25/465/587/2525, ni IMAP, ni SSH | `tofu test` de `tofu/pangolin` (`drill_is_isolated_from_production`) |
| Le serveur est pris pour Pangolin ou flip | label `role=drill` : groupe Ansible `drill` seul (ni `hetzner`, ni `pangolin`, ni `flip`), aucun réseau privé, aucun NAT | `tofu test`, `.github/scripts/test_hetzner_inventory.py` |
| Ports publiés par Docker (beszel 8090, vmauth 9428) | pare-feu Hetzner : seul tcp/22, depuis l'IP du poste en /32 ; IPv6 coupée ; ces rôles ne sont de toute façon pas joués | `tofu test` |
| Clé d'hôte SSH | Tofu génère l'ed25519 et l'injecte par cloud-init ; la ligne `known_hosts` vient du state (`ansible/known_hosts.drill`, hors dépôt) ; `StrictHostKeyChecking=yes` ; aucun `ssh-keyscan` | `drill.tf`, `hetzner.py` |
| Un `docker.yml` lancé sans y penser | `hosts: "{{ drill_target \| default('docker') }}"` : sans `-e drill_target=drill`, la production ; et un `assert` refuse l'hôte dont le groupe `drill` et `drill_mode` ne vont pas ensemble | `docker.yml` |
| Un merge qui déploie pendant l'exercice | rien du dépôt n'est modifié par l'exercice ; mais **un merge sur `main` déploie la production** comme d'habitude : ne pas fusionner de PR touchant les rôles pendant l'exercice (comme dans perte-totale-maison) | `docs/conventions/ci.md` |

**Ne jamais lancer `backup.yaml` pour la copie** : elle autoriserait une clé de la
copie chez un sous-compte de production, en écriture. La copie n'a pas de clé
propre ; elle utilise celle de `restore-test`.

Les applis qui, restaurées, agiraient d'elles-mêmes sur HTTPS (flux RSS de
FreshRSS, robots de Karakeep, `webhooks` enregistrés dans une base) tournent
avec les données de la production : rien ne les en empêche à part le temps (quelques
heures) et l'absence d'identifiants de production dans leur environnement (OIDC,
URL push, clés IA vides). Un webhook HTTPS déjà enregistré dans une base partirait :
à relire dans l'appli avant de laisser tourner longtemps.

## Coût

Serveur `cx53` par défaut (16 vCPU, 32 Gio, 320 Go ; la VM de production a 3
cœurs, 12 Gio et 190 Gio dont ~105 Gio écrits : le `cx43`, 160 Go, serait trop
juste avec les images Docker) à Falkenstein (`fsn1`, le datacenter de la Storage Box). Prix
horaire : **à confirmer dans la console ou par `hcloud server-type describe cx53`
avant l'`apply`** : l'ordre de grandeur est de quelques centimes l'heure, donc
moins de 1 € pour l'exercice. Une IPv4 publique à 0,50 €/mois au prorata.
Aucun volume, aucune sauvegarde Hetzner.

Le 09/11/2026, le `cx53` était indisponible à fsn1 (`resource_unavailable` à
l'`apply`, pare-feu et clé déjà créés). Les types disponibles se lisent dans
`GET /v1/server_types` (champ `locations[].available` ; l'ancien
`/v1/datacenters` est retiré). L'exercice a tourné sur un `cpx42` (8 vCPU AMD,
16 Gio, 320 Go, 0,13 €/h TTC), passé par `server_type="cpx42"` dans le `-var
drill` : largement assez, la restauration ne monte jamais au-dessus du disque
et du réseau.

## Diagnostic : prérequis

L'étage 1 de [perte-totale-maison.md](perte-totale-maison.md) est passé : poste,
clé age, SOPS, `HCLOUD_TOKEN` et clés du state dans l'environnement de `mise`,
`git submodule update --init`, `mise run init`. Pour l'exercice, un poste normal
suffit. Une session où `sops` et `tofu -chdir=tofu/pangolin output` répondent.

## Réparation : la procédure

Chaque étape porte un repère (T0…) de la feuille de temps. Démarrer le chronomètre
à T0.

**T0. Créer le serveur** (depuis un clone à jour de `main`, hors checkout principal) :

```bash
ip=$(curl -s https://ifconfig.me)
mise exec -- tofu -chdir=tofu/pangolin plan  -var "drill={enabled=true,allowed_ssh_cidrs=[\"$ip/32\"]}"
```

Le plan ne doit montrer **que** la création de `tls_private_key.drill_host[0]`,
`hcloud_firewall.drill[0]` et `hcloud_server.drill[0]`, rien d'autre (sinon le
state a dérivé : s'arrêter). Puis, même `-var`, `apply`. Sylvain applique.

**T1. Clé d'hôte et accès.** La ligne `known_hosts` se lit dans le state, pas sur
le réseau ; la clé de borg va dans un fichier privé, jamais affichée :

```bash
mise exec -- tofu -chdir=tofu/pangolin output -raw drill_known_hosts_line > ansible/known_hosts.drill
( umask 077; mise exec -- tofu -chdir=tofu/pangolin output -raw storage_box_restore_test_ssh_private_key > "$XDG_RUNTIME_DIR/drill_borg_key" )
cd ansible
ansible-galaxy install -r requirements.yml   # worktree neuf : sans, « role geerlingguy.docker was not found »
ansible-inventory --graph            # docker-drill sous @drill, et nulle part ailleurs
ansible drill -m ping
```

**T2. Base : Docker, durcissement, borgmatic en lecture seule, outils.**

```bash
ansible-playbook docker.yml -e drill_target=drill -e docker_drill_key_file="$XDG_RUNTIME_DIR/drill_borg_key" --tags setup
```

Contrôle sur la copie : `systemctl is-enabled borgmatic.timer` donne `masked`.

**T3. Toutes les applis, à vide** (compose, `.env`, unités `dc@`, configurations
borgmatic ; les images se tirent ici : c'est le temps de téléchargement, mesuré
à part) :

```bash
ansible-playbook docker.yml -e drill_target=drill -e docker_drill_key_file="$XDG_RUNTIME_DIR/drill_borg_key"
```

Puis **une seconde fois, même commande avec `--tags app`**, une fois les applis
démarrées : Ansible ne repère une base SQLite (à exclure, à copier avant
sauvegarde) que sur le disque ; au premier passage elle n'existe pas encore, et
la configuration de l'appli ne la liste pas. Sans ce second passage,
`drill-restore-app` s'arrête sur ce constat plutôt que de relancer l'appli à vide.

**T4. Restaurer chaque appli**, sur la copie (`ssh sylvain@<drill_ipv4>`, en root).
Étage 1 d'abord (Nextcloud, Dawarich, Papra), puis le reste ; la durée de chaque
appli est dans sa ligne `RESTORE-RESULT` :

```bash
for app in nextcloud dawarich papra; do sudo drill-restore-app "$app"; done
for f in /etc/borgmatic.d/*.yaml; do
  a=$(basename "$f" .yaml)
  case "$a" in nextcloud|dawarich|papra) continue ;; esac   # déjà faites
  sudo drill-restore-app "$a"
done
```

`drill-restore-app` ne fait que lire Borg : si le fichier de configuration ne
passe pas par `borg-readonly`, il s'arrête. Il remet les copies SQLite avec
leur propriétaire et leur mode WAL, rejoue les dumps PostgreSQL et MariaDB, puis
relance l'appli. Un échec s'arrête sur la première erreur : lire le message,
corriger, relancer l'appli seule (l'extraction repart de zéro).

**T5. Reconvergence** : les compose et `.env` extraits sont ceux de production ;
rejouer Ansible remet ceux du dépôt, et garantit que rien n'a changé :

```bash
ansible-playbook docker.yml -e drill_target=drill -e docker_drill_key_file="$XDG_RUNTIME_DIR/drill_borg_key" --tags app
```

**T6. Contrôles** : `sudo drill-check` (tableau « Vérification » plus bas), puis,
à l'œil sur trois applis au moins (Nextcloud, Papra, Dawarich), par un tunnel :
`ssh -L 18080:$(ssh sylvain@<ip> docker inspect -f '{{(index .NetworkSettings.Networks "newt").IPAddress}}' papra):1221 sylvain@<ip>`
puis `http://127.0.0.1:18080`. Le SSO de la production n'existe pas ici : la
connexion locale de l'appli, avec le compte du foyer, suffit pour voir ses données.

**T7. Détruire** (voir plus bas).

### Feuille de temps

À remplir pendant chaque exercice (hh:mm, durées en minutes) ; noter ce qui a bloqué.

Exercice du 09/11/2026 (cpx42, fsn1 ; durées par appli en secondes, tirées des
lignes `RESTORE-RESULT`) :

| Étape | Début | Fin | Durée | Remarque |
|---|---|---|---|---|
| T0 création du serveur (apply + SSH joignable) | 21:50 | 21:52 | 2 | `cx53` indisponible : `cpx42` |
| T1 clé d'hôte, inventaire, ping | 21:52 | 21:52 | < 1 | `tofu -chdir=tofu/proxmox init` nécessaire pour que l'inventaire se charge |
| T2 base (`--tags setup`) | 21:52 | 21:57 | 5 | dont deux échecs : rôles Galaxy absents ; masque de `borgmatic.timer` (corrigé) |
| T3 applis à vide (dont tirage des images) | 21:57 | 22:06 | 9 | 8 min le premier passage, 1 min le second (`--tags app`) |
| T4 Nextcloud (extraction / base) | 22:06 | 22:08 | 1,6 | 98 s : extraction 47, MariaDB 45 |
| T4 Dawarich | 22:10 | 22:11 | 1,5 | 92 s (base 60, 2,4 M points) ; échec au premier essai : PostGIS (corrigé) |
| T4 Papra | 22:09 | 22:09 | 0,2 | 11 s |
| T4 les autres | 22:11 | 22:20 | 9 | betisier 36, grocy 14, homebox 5, jellystat 33, karakeep 84, monica_v4 37, ntfy 4, speedtest_tracker 16, trek 35, wiki 44, wishlist 5, yamtrack 8 ; grocy relancée (base créée à la première requête) ; openwebui et rss : voir Constats |
| T5 reconvergence | 22:20 | 22:22 | 2 | |
| T6 contrôles (`drill-check`) | 22:22 | 22:27 | 5 | 4 échecs : Nextcloud (sonde, corrigée), Open WebUI ×2, rss ; contrôle à l'œil par tunnel non fait |
| **Total T0 à T6** | 21:50 | 22:27 | **37** | dont ~10 min de corrections ; les restaurations seules : ~13 min |
| T7 destruction vérifiée | 22:25 | 22:27 | 2 | 3 destructions, API : 0 serveur, volume, pare-feu, image `role=drill` |

### Constats de l'exercice (09/11/2026)

- **FreshRSS (`rss`) non restaurée.** Sur une installation vide, FreshRSS ne
  crée sa base `data/users/<compte>/db.sqlite` qu'au bout de son assistant
  d'installation : Ansible ne la voit pas, la configuration borgmatic n'en
  liste aucune, et `drill-restore-app` refuse de remettre les copies de
  l'archive (il ne sait pas où). Corrigé : le rôle `rss` déclare le compte
  (`rss_default_user`) et l'image s'installe seule au premier démarrage
  (`FRESHRSS_INSTALL`, `FRESHRSS_USER`) ; la base existe avant le second
  passage `--tags app`, comme pour les autres applis. À confirmer au prochain
  exercice (l'archive du 10/11 porte bien la copie
  `opt_apps_rss_freshrss_data_users_sylvain_db.sqlite`).
- **Open WebUI : pas d'archive.** L'appli venait d'être déployée, sa première
  sauvegarde n'avait pas tourné : rien à restaurer, base vide. Attendu.
- **Applis dont la base SQLite naît à la première requête** (Grocy) : le second
  passage `--tags app` ne suffit pas tant que personne n'a ouvert l'appli. Faire
  une requête HTTP sur chaque appli avant ce passage (ce qu'a fait l'exercice
  pour Grocy).
- **PostgreSQL avec extension** (Dawarich, PostGIS) : le dump ne peut pas
  supprimer l'extension dont dépend une table créée au démarrage à vide.
  `drill-restore-app` recrée désormais chaque base PostgreSQL vide avant de
  rejouer le dump.
- **Nextcloud** refuse une sonde par IP (`Trusted domain error`, 400) :
  `drill-check` envoie maintenant `Host: nextcloud`. Données vérifiées
  (`installed: true`, 35.0.2, 25 864 fichiers).
- Débit de la Storage Box, même datacenter : 47 s pour l'archive de Nextcloud,
  79 s pour celle de Karakeep. Un sinistre réel reconstruirait sans doute
  ailleurs, plus lentement.

Ce qui change la lecture : le débit de la Storage Box (même datacenter que la
copie, alors qu'un sinistre réel reconstruirait ailleurs) ; le disque NVMe du
cloud, bien plus rapide que le SSD SATA de la VM de production ; le temps d'accès
au Docker Hub. Le noter dans « Remarque » avant de recopier un chiffre dans la
matrice.

## Vérification : applis de la VM docker

`drill-check` fait les deux premières colonnes de chaque ligne (sonde HTTP sur
l'IP du conteneur, sans suivre de redirection, 200 à 399 ; tables non vides, comme
le test de restauration de la CI). Les applis sans dépôt Borg (`bentopdf`,
`enclosed`, `pairdrop`, `docs_site`) n'ont que la sonde.

| Appli (dépôt) | Bases | Sonde (conteneur:port chemin) | Preuve des données |
|---|---|---|---|
| beszel | sqlite | exclu (rôle non joué) | non vérifié sur la copie : le test de la CI le fait |
| betisier | mysql | `betisier:80/` | `betisier` : `personne`, `citation` |
| dawarich | postgresql | `dawarich-app:3000/api/v1/health` | `dawarich` : `users`, `points` |
| grocy | sqlite | `grocy:80/robots.txt` | `grocy.db` : `users` |
| healthlog | postgresql | exclu (jetons Withings) | non vérifié sur la copie : test de la CI et restauration d'essai de [healthlog.md](healthlog.md) |
| homebox | sqlite | `homebox:7745/api/v1/status` | `homebox.db` : `users`, `groups` |
| jellystat | postgresql | `jellystat:3000/auth/isconfigured` | `jellystat` : `app_config` |
| karakeep | sqlite | `karakeep:3000/api/health` | `db.db` : `user`, `bookmarks` |
| monica_v4 | mysql | `monica_v4:80/` | `monica` : `users`, `accounts` |
| nextcloud | mysql | `nextcloud:80/status.php` | `nextcloud` : `oc_appconfig`, `oc_storages`, `oc_filecache` ; à l'œil : un fichier récent s'ouvre |
| ntfy | sqlite | `ntfy:8080/v1/health` | `user.db` : `user`, `user_token` |
| openwebui | sqlite | `openwebui:8080/health` | `webui.db` : `user`, `auth` |
| papra | sqlite | `papra:1221/api/health` | `db.sqlite` : `users`, `documents` ; à l'œil : un document s'ouvre |
| rss | sqlite | `rss:80/api/` | `db.sqlite` : `category`, `feed` |
| speedtest_tracker | sqlite | `speedtest-tracker:80/api/healthcheck` | `database.sqlite` : `users`, `results` |
| trek | sqlite | `trek:3000/api/health` | `travel.db` : `users`, `trips` |
| wiki | mysql | `bookstack:80/login` | `bookstack` : `users` |
| wishlist | sqlite | `wishlist:3280/favicon.ico` | `prod.db` : `user` |
| yamtrack | sqlite | `yamtrack:8000/health/` | `db.sqlite3` : `users_user` |

`beszel`, `healthlog`, `victoria_logs`, `homepage` ne sont pas rejoués : voir le
[README du rôle `docker_drill`](../../ansible/roles/docker_drill/README.md).
Observation : la table de `drill-check.py` et `apps.json` sont gardées alignées
par un test de la CI (`test_drill_check.py`).

Connus pour gêner le contrôle : `betisier` se réinitialise chaque jour
(`betisier-reset.timer`) : lancer `drill-check betisier` juste après sa restauration ;
les SQLite des applis qui font un VACUUM au démarrage peuvent changer de taille.

## Destruction (fait partie de la procédure)

```bash
shred -u "$XDG_RUNTIME_DIR/drill_borg_key"; rm -f ansible/known_hosts.drill
mise exec -- tofu -chdir=tofu/pangolin plan      # sans -var drill
```

Le plan ne doit montrer **que** la destruction des trois ressources du T0
(serveur, pare-feu, clé TLS) ; puis `apply`. Vérifier, deux fois :

- `tofu -chdir=tofu/pangolin output drill_ipv4` donne `null` ;
- la console Hetzner (ou `GET /v1/servers?label_selector=role=drill` de l'API)
  ne liste **ni serveur, ni volume, ni pare-feu, ni snapshot** `role=drill`.

La clé privée de l'hôte de la copie vit chiffrée dans le state jusqu'à cette
étape, puis disparaît avec la ressource. Si l'`apply` échoue en route (serveur à
moitié détruit), recommencer ; ne pas laisser dormir un serveur chargé de données
personnelles. Lancer ensuite un `apply` ordinaire de `tofu/pangolin` reste
sans effet sur la production : `drill` éteint est son état par défaut.

## Sinistre réel : ce qui diffère (non préparé)

La copie est faite pour être jetée : sans Newt, sans sauvegarde, sans compte
Borg en écriture. La faire devenir la VM docker de production est une étape
**distincte, non rédigée ni testée**, à décider le jour venu (et à compléter ici
avec ce que l'exercice aura montré) :

1. Elle exige un inventaire où l'hôte s'appelle `docker` (`proxmox.py` lit le
   state de `tofu/proxmox`, qui n'existe plus : un fichier d'inventaire à la main
   avec `ansible/known_hosts.drill` comme `GlobalKnownHostsFile`).
2. Sortir du mode exercice : `drill_mode` faux, hôte hors du groupe `drill`, pare-feu
   Hetzner à rouvrir selon le besoin (les applis passent par Newt : seul SSH).
3. `docker.yml --tags setup`, puis `backup.yaml` (clé de root de la copie chez le
   sous-compte `backup-docker`, en écriture : les dépôts de production reprennent),
   puis le rôle `newt` (les identifiants du site `docker` : Pangolin route de
   nouveau vers la copie, sans changement de DNS).
4. Débloquer HealthLog, Beszel, Homepage, VictoriaLogs et les rapports (les
   rôles exclus de `docker.yml`).
5. Ne jamais allumer `newt` avec l'ancienne VM encore vivante.

## Prévention

- Jouer l'exercice une première fois, remplir la feuille, recopier le total dans
  [matrice-des-donnees.md](../matrice-des-donnees.md) (ligne « VM docker entière »)
  et corriger [perte-totale-maison.md](perte-totale-maison.md) (étage 4 :
  durées réelles), puis chaque année.
- Revoir la liste des rôles exclus et les « effets sortants » à chaque appli
  ajoutée à la VM docker (README de `docker_drill`).
- Garder `tofu test` de `tofu/pangolin` vert : il prouve le pare-feu et l'absence
  de réseau privé.
