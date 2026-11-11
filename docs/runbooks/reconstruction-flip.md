# Reconstruction de flip depuis Borg

**Jamais joué.** Ce runbook est écrit d'après `ansible/flip.yml`, `tofu/pangolin/flip.tf`
et les répétitions de [reconstruction-pangolin.md](reconstruction-pangolin.md) et de
[reconstruction-vm-docker.md](reconstruction-vm-docker.md) ; chaque étape est à
confirmer au premier exercice (la démo se prête à l'essai : même rôle, son propre
dépôt Borg).

**Pas de reprise rapide par image Hetzner**, et c'est voulu (décision du
2026-11-11) : `backups = false` sur `hcloud_server.flip`, on n'active pas les
sauvegardes Hetzner de flip (quelques euros par mois). **Borg est la seule copie**
de Flip Planning (production et démo) : un dépôt Borg abîmé ou une clé
`backup_passphrase` perdue, et il n'y a plus rien
([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md), point 6, pour les
instantanés de la Storage Box).

## Symptôme

Le serveur `flip` est perdu ou irrécupérable (disque corrompu, compromission,
suppression) et [flip-injoignable.md](flip-injoignable.md) n'a pas suffi : Flip
Planning, Postiz et Promptoramix sont hors ligne. flip n'a pas d'IP publique : la console
Hetzner est le seul accès hors réseau.

## Diagnostic

- Épuiser d'abord les réparations de [flip-injoignable.md](flip-injoignable.md)
  (route ou DNS effacés, Newt, console Hetzner, mode rescue).
- **Pangolin doit être debout** : flip lui doit son Internet (NAT), son accès
  SSH (rebond) et son Newt. Pangolin perdu aussi : d'abord
  [reconstruction-pangolin.md](reconstruction-pangolin.md).
- Les dépôts Borg se lisent depuis n'importe quel hôte avec le sous-compte en
  lecture seule `restore-test` (même méthode que pour Pangolin) : vérifier que
  `flip_planning`, `demo_planning` et `postiz` ont une archive récente avant de détruire
  quoi que ce soit.
- Ce qui n'est **pas** dans Borg : Promptoramix (journal de coups, hors
  sauvegarde, `docs/matrice-des-donnees.md`), la démo Keycloak et la vitrine
  publique (en pause, aucune sauvegarde : leurs données n'existaient que sur le
  disque).

## Réparation

1. **Recréer le serveur** (`tofu/pangolin`). `hcloud_server.flip` porte
   `prevent_destroy = true` : le lever temporairement dans
   `tofu/pangolin/flip.tf`, puis

   ```bash
   cd tofu/pangolin
   tofu plan -replace=hcloud_server.flip    # relire : seul le serveur bouge
   tofu apply -replace=hcloud_server.flip   # Sylvain applique
   ```

   Remettre `prevent_destroy` ensuite. L'IP privée est fixe
   (`var.flip_server.private_ip`) : l'inventaire, la CI et `flip.internal` ne
   changent pas. La route NAT (`hcloud_network_route.nat`) vise Pangolin, pas
   flip : elle reste.

2. **Clé d'hôte** : relever l'empreinte depuis la **console Hetzner**
   (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), jamais par
   `ssh-keyscan`, puis remplacer la ligne `flip,10.0.1.10` et le commentaire
   d'empreinte dans `ansible/known_hosts`
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)).

3. **Base de la machine : NAT, Docker, sécurité, Newt, clé de sauvegarde.**
   **Ordre imposé** : le NAT d'abord, parce que tout le reste (paquets, images,
   Newt) sort par Pangolin ; `nat_client` est le premier rôle de `flip.yml`.
   **Jamais `flip.internal`** pour Ansible : cette ressource passe par le Newt
   de flip, qu'un play redémarre (il couperait sa propre connexion) ; Ansible
   passe par le rebond de `inventory/hetzner.py`.

   ```bash
   cd ansible
   ansible-playbook flip.yml --tags setup --check --diff   # puis sans --check
   ansible-playbook 00-setup.yaml --limit flip             # paquets, clé github-actions.pub (sans elle la CI n'entre pas)
   ansible-playbook backup.yaml                            # autorise la nouvelle clé chez le sous-compte flip
   ```

   `--tags setup` ne pose aucune appli : le Newt reprend les identifiants du
   site `flip` lus dans le state de `pangolin_config` (`flip_newt_id` et
   `flip_newt_secret`, inchangés puisque le site Pangolin existe toujours) et
   se reconnecte seul. `backup.yaml` lit la clé de `docker`, `pi`, `pangolin`,
   `flip`, `nas` et `pve` et refuse tout si l'une manque : limiter aux hôtes
   présents (pas `--limit` : `-e '{"backup_storage_box_hosts": ["flip"]}'`, comme à l'étage 4 de [perte-totale-maison.md](perte-totale-maison.md)).

4. **Les applis, à vide, sans leur sauvegarde.**

   ```bash
   ansible-playbook flip.yml --skip-tags backup
   ```

   Les piles démarrent **vides**. `--skip-tags backup` ne dépose pas les configs
   borgmatic des applis : **ne pas passer `--tags backup` avant la
   restauration**, sinon une archive de bases vides s'ajoute aux dépôts de
   production et compte dans la rétention (c'est le piège de l'en-tête de
   `flip.yml`).

5. **Restaurer chaque instance depuis Borg**, `flip_planning` (production)
   d'abord, puis `demo_planning`. Procédure de
   [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md) et de
   [../backup-restore.md](../backup-restore.md), à adapter : le dépôt n'a pas
   de configuration borgmatic sur la machine neuve (étape 4), donc l'`extract`
   et le `restore` se font avec le sous-compte `restore-test` en lecture seule
   (méthode de [reconstruction-pangolin.md](reconstruction-pangolin.md),
   « Diagnostic ») ou après un `--tags flip_planning,backup` volontaire une fois
   la restauration faite. Pour chaque instance :

   - arrêter l'appli (`systemctl --user stop dc@flip_planning`), démarrer
     **la base seule** (`docker compose up -d postgres` dans
     `/opt/apps/<instance>` : `postgres` est le service du compose, son
     conteneur s'appelle `<prefixe>-db`), rejouer le dump PostgreSQL avec
     `pg_restore` ; `compose.yaml` et `pgadmin` sont déjà reposés par
     l'étape 4, ne pas les recopier de l'archive ;
   - redémarrer l'appli, puis vérifier avec les animateurs et le planning réels.
   - **Postiz** : rejouer les trois dumps (`postiz`, `temporal`,
     `temporal_visibility`) dans le PostgreSQL seul, **avant** de démarrer
     `temporal`, et remettre `uploads/` (`ansible/roles/postiz/README.md`,
     « Sauvegarde »).

   Les sauvegardes de la nuit n'ont pas encore été reposées : la dernière
   archive saine reste celle d'avant la panne.

6. **Remettre la sauvegarde en route**, seulement une fois les données de chaque
   instance revenues :

   ```bash
   ansible-playbook flip.yml --tags backup
   ```

   Ce passage pose les configs borgmatic des applis, le `repo-create`
   (idempotent : les dépôts existent) et l'URL push des moniteurs « Backup … ».
   Il repère aussi les bases SQLite (aucune aujourd'hui sur flip, mais c'est ce
   second passage qui les repérerait).

7. **CI** : committer par PR la ligne de `ansible/known_hosts` (étape 2) avant le
   prochain déploiement. **Pas de merge qui déploie pendant la reprise** : un
   merge sur `main` qui touche `ansible/roles/**` ou `flip.yml` lancerait
   `deploy-docker-app` sur un flip à moitié restauré
   ([deploiement-ci-casse.md](deploiement-ci-casse.md)).

## Vérification

```bash
cd ansible
mise run ssh_flip
systemctl --user list-units 'dc@*' --state=failed   # vide (demo_planning_kc est arrêtée exprès)
curl -sSI https://deb.debian.org | head -1          # la sortie par Pangolin marche
```

- Le site `flip` est en ligne dans Pangolin ; les URL de production et de démo
  de Flip Planning répondent derrière leurs règles habituelles.
- Les moniteurs Uptime Kuma de flip sont verts (nat, mises à jour, sauvegardes).
- Le lendemain, les moniteurs « Backup » de `flip_planning` et `demo_planning`
  sont verts, et la nouvelle archive contient bien les dumps.
- `tofu plan` dans `tofu/pangolin_config` ne montre pas de dérive.

## Prévention

- Jouer ce runbook une fois sur la démo, puis corriger ce fichier de ce qui a
  surpris (c'est la seule façon de lui retirer le « jamais joué » du titre).
- Pas d'image Hetzner pour flip (décision du 2026-11-11) : le temps de reprise
  est celui d'une reconstruction complète, non mesuré (estimation : ~1 h de
  [matrice-des-donnees.md](../matrice-des-donnees.md), plus le serveur).
- Surveiller les moniteurs « Backup » de flip : c'est la seule copie.
