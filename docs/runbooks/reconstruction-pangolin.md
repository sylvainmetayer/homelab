# Reconstruction complète de Pangolin depuis Borg

Le serveur en place vient d'un ancien snapshot Packer (Packer a quitté le
dépôt). Une reconstruction repart de `debian-13` nu + `user_data.yaml`, puis
`00-setup.yaml` et `pangolin.yaml`, puis la restauration de `/opt/pangolin`
(config, base SQLite, certificats Let's Encrypt) depuis son dépôt Borg. Les
sauvegardes Hetzner de la VM sont désactivées (`backups = false`) : Borg est
la seule copie.

## Symptôme

La VM Pangolin est perdue ou irrécupérable (disque corrompu, compromission,
suppression). Tout le homelab public est coupé, flip n'a plus d'Internet, la
CI ne déploie plus.

## Diagnostic

Avant de reconstruire, s'assurer qu'une réparation ne suffit pas
([pangolin-injoignable.md](pangolin-injoignable.md)) : console Hetzner,
mode rescue. Une reconstruction change l'IP publique et la clé d'hôte SSH.

Vérifier que le dépôt Borg de Pangolin est lisible depuis un autre hôte de
confiance : à vérifier (chaque sous-compte ne voit que son hôte ; le compte
principal voit `backup/pangolin/pangolin`).

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

   Rendre au fichier SQLite le propriétaire attendu par le conteneur : à
   vérifier (comparer avec `stat -c %u:%g` sur un autre fichier de
   `/opt/pangolin/config/db/`).

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

## Prévention

- Faire un exercice à blanc de temps en temps : extraire la dernière archive
  de Pangolin dans `/root/restore` et vérifier que la base SQLite s'ouvre
  (`sqlite3 <fichier> 'pragma integrity_check'`).
- Une Primary IP Hetzner réservée éviterait le changement d'IP (DNS,
  `known_hosts`) : non utilisée aujourd'hui.
