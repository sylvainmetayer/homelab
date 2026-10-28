# Reconstruction complète de Pangolin depuis Borg

Le serveur en place vient d'un ancien snapshot Packer (Packer a quitté le
dépôt). Une reconstruction repart de `debian-13` nu + `user_data.yaml`, puis
`00-setup.yaml` et `pangolin.yaml`, puis la restauration de `/opt/pangolin`
(config, base SQLite, certificats Let's Encrypt) depuis son dépôt Borg.

**Avant tout cela, la reprise rapide** : les sauvegardes Hetzner de la VM
sont actives (`backups = true`, 7 images glissantes, une par jour). Si le
serveur existe encore chez Hetzner et que la panne n'est pas une
compromission, restaurer l'image de la veille (console Hetzner → serveur →
Backups → Restore) : même IP, même clé d'hôte, pas de DNS ni de
`known_hosts` à toucher, base SQLite de la veille. Après une compromission,
ou si le projet Hetzner est perdu, c'est la reconstruction ci-dessous, depuis
Borg (hors Hetzner).

## Symptôme

La VM Pangolin est perdue ou irrécupérable (disque corrompu, compromission,
suppression). Tout le homelab public est coupé, flip n'a plus d'Internet, la
CI ne déploie plus.

## Diagnostic

Avant de reconstruire, s'assurer qu'une réparation ne suffit pas
([pangolin-injoignable.md](pangolin-injoignable.md)) : console Hetzner,
mode rescue. Une reconstruction change l'IP publique et la clé d'hôte SSH.

Le dépôt Borg de Pangolin se lit depuis n'importe quel hôte avec le
sous-compte en lecture seule `restore-test` (clé : `tofu output -raw
storage_box_restore_test_ssh_private_key` dans `tofu/pangolin`, dépôt
`ssh://<user>@<server>:23/./pangolin/pangolin`, `<user>` et `<server>` :
outputs `storage_box_restore_test_username` et `_server`, clé d'hôte
`backup_storage_box_host_key` pour `[<server>]:23`, phrase de passe
`backup_passphrase`, `borg --bypass-lock`) :
vérifié lors de la répétition du 2026-10-28 (voir « Répétition » plus bas).

## Réparation

1. **Recréer le serveur** (`tofu/pangolin`).
   - Serveur déjà supprimé chez Hetzner : `mise run plan` propose de le
     recréer, `mise run apply`.
   - Serveur encore là mais irrécupérable : `hcloud_server.pangolin` porte
     `prevent_destroy = true`. Le lever temporairement dans
     `tofu/pangolin/pangolin.tf`, puis :

     ```bash
     cd tofu/pangolin
     tofu plan -replace=hcloud_server.pangolin    # relire : seul le serveur (et ce qui en dépend) bouge
     tofu apply -replace=hcloud_server.pangolin
     ```

     Remettre `prevent_destroy` ensuite.

   `var.image` vaut `debian-13` par défaut (`tofu/pangolin/variables.tf`) :
   le nouveau serveur part de l'image publique, plus du snapshot Packer. La route NAT de flip
   (`hcloud_network_route.nat`) suit l'IP privée du nouveau serveur.

2. **DNS** : les enregistrements A de `tofu/dns` lisent l'IP dans le state de
   `tofu/pangolin`. `tofu plan` puis `tofu apply` dans `tofu/dns`.

3. **Clé d'hôte** : relever l'empreinte depuis la **console Hetzner**
   (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), jamais par
   `ssh-keyscan`, puis remplacer la ligne `pangolin,pangolin.sylvain.cloud,<IP>`
   et le commentaire d'empreinte dans `ansible/known_hosts`
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)).

4. **Configuration de base, puis la clé de sauvegarde** :

   ```bash
   cd ansible
   ansible-playbook 00-setup.yaml --limit pangolin
   ansible-playbook pangolin.yaml --tags setup    # rôle borgmatic : nouvelle clé de root
   ansible-playbook backup.yaml                   # l'autorise chez le sous-compte backup-pangolin
   ```

5. **Restaurer `/opt/pangolin` avant de lancer la pile.** Le rôle `pangolin`
   crée les dossiers et la config, mais la base SQLite (ressources,
   utilisateurs, sites, SSO) et `acme.json` viennent de Borg. Il faut que
   `borgmatic` ait sa config `/etc/borgmatic.d/pangolin.yaml` : la déposer
   avec `ansible-playbook pangolin.yaml --tags backup`. Puis, en root :

   ```bash
   borgmatic=/root/.local/bin/borgmatic
   config=/etc/borgmatic.d/pangolin.yaml
   $borgmatic list --config $config
   mkdir -p /root/restore/pangolin
   $borgmatic extract --config $config --archive latest --destination /root/restore/pangolin
   systemctl stop pangolin 2>/dev/null || true
   cp -a /root/restore/pangolin/opt/pangolin/. /opt/pangolin/
   cp /root/restore/pangolin/var/lib/borgmatic-sqlite/pangolin/opt_pangolin_config_db_db.sqlite /opt/pangolin/config/db/db.sqlite
   ```

   Le conteneur tourne en root : le fichier SQLite reste `root:root`
   `0644`, comme le crée le `cp` de root (umask 022 ; vérifié le
   2026-10-28). L'archive pèse
   ~10 Go (la base ~2,3 Go, et `config/db/backups/`, les copies que Pangolin
   fait avant chaque migration, ~7,7 Go) : compter ~3 min d'extraction et
   ~20 Go libres sur le disque.

6. **Le reste de la play** (pile, NAT, sécurité) :

   ```bash
   ansible-playbook pangolin.yaml --check --diff
   ansible-playbook pangolin.yaml
   ```

7. **CI** : la CI joint Pangolin par `pangolin.sylvain.cloud` et vérifie sa
   clé contre `ansible/known_hosts` : committer la nouvelle ligne (étape 3)
   par PR avant le prochain déploiement.

## Vérification

```bash
cd /opt/pangolin && docker compose ps
curl -sSI https://pangolin.sylvain.cloud | head -1
```

- Le tableau de bord montre les ressources et les sites ; chaque Newt
  (docker, pi, flip, LXC) se reconnecte seul (même endpoint
  `https://pangolin.sylvain.cloud`, mêmes identifiants, puisque la base est
  restaurée).
- `tofu plan` dans `tofu/pangolin_config` ne montre pas de dérive importante.
- flip sort de nouveau sur Internet ([flip-injoignable.md](flip-injoignable.md)).
- Le lendemain, le moniteur de sauvegarde de Pangolin est UP.

## Répétition

Faite le 2026-10-28 sur une VM jetable (`cx23`, `debian-13`, sans réseau
privé), détruite ensuite : ~45 min de bout en bout, sans incident bloquant.
Base intègre (`pragma integrity_check` : ok, 23 ressources, 6 sites),
certificats Let's Encrypt restaurés valides, pile (pangolin, gerbil,
traefik, crowdsec) saine, pages servies avec `curl --resolve`. Ce qu'elle a
appris :

- **Toujours partir de `main` à jour** : une branche ancienne déploie un
  rôle d'avant les derniers merges (la première passe a oublié CrowdSec).
- **Sur un serveur pas encore rattaché au réseau privé**, `nat_gateway`
  échoue (« 10.0.0.1 and the default route both go through eth0 ») :
  normal, le rattachement vient de `tofu/pangolin`. Pour une répétition,
  `--skip-tags nat`.
- **Viser la VM, jamais le vrai serveur** : l'hôte `pangolin` de
  l'inventaire vient du state (`hetzner.py`). La répétition passe donc un
  inventaire à elle (`-i /chemin/inventory.ini`, une ligne `[hetzner]` puis
  `pangolin ansible_host=<IP de la VM> ansible_user=sylvain` : le nom
  `pangolin` garde ses `host_vars`) et son propre fichier de clés d'hôte
  (`ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o
  UserKnownHostsFile=/chemin/known_hosts -o StrictHostKeyChecking=yes"`),
  sans toucher à `ansible/known_hosts`. Chaque commande ad hoc sur la VM
  (`systemctl …`) passe par ce même inventaire ou par `ssh` vers son IP.
- **Pour répéter sans toucher à la production** : jamais `backup.yaml` (il
  remplacerait la clé du vrai sous-compte de Pangolin), restaurer par
  `restore-test` ; `--skip-tags backup,beszel_agent,monitoring` (un second
  agent Beszel avec le même jeton ferait clignoter le vrai) ;
  `systemctl disable --now borgmatic.timer` après `--tags setup` (sans la
  config d'app, sautée par `--skip-tags backup`, il échoue sans rien
  pousser ; mais un `--tags backup` y poserait l'URL push du vrai moniteur
  de sauvegarde, que la sauvegarde, clé non autorisée, passerait DOWN à
  01:00) ; `geoipupdate.timer` pousse sur le vrai moniteur `GeoIP Pangolin`
  (mercredi 02:30) : le couper aussi si la VM passe la nuit ;
  `-e ssh_login_notify_enabled=false` sur `00-setup.yaml` ; une clé d'hôte
  générée d'avance et donnée par `ssh_keys` de cloud-init, ce qui évite
  `ssh-keyscan`. Les DNS ne bougent pas : les Newt restent sur le vrai
  serveur.

## Prévention

- Faire un exercice à blanc de temps en temps : extraire la dernière archive
  de Pangolin dans `/root/restore` et vérifier que la base SQLite s'ouvre
  (`sqlite3 <fichier> 'pragma integrity_check'`).
- Une Primary IP Hetzner réservée éviterait le changement d'IP (DNS,
  `known_hosts`) : non utilisée aujourd'hui.
