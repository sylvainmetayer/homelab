# Perte de la clé age perso, d'une clé SSH ou d'un poste

## Symptôme

- `sops` refuse de déchiffrer (`no key could decrypt the data key`) :
  `~/.age.key` (chemin de `.sopsrc`) perdue ou abîmée.
- La clé SSH perso (agent KeePassXC, `~/.ssh/keepassxc.pub` côté client)
  n'ouvre plus les hôtes.
- Un poste perdu ou volé : c'est les deux à la fois, avec en plus le risque
  qu'un tiers les ait.

## Diagnostic

Ce qui déchiffre quoi (`.sops.yaml`) :

| Destinataire age | `secrets.sops.yaml` (racine) | `ansible/secrets.sops.yaml` |
|---|---|---|
| `perso` | oui | oui |
| `pro` | oui | oui |
| `secours` | oui | oui |
| `github-actions` (CI) | non | oui |

Où sont rangées la clé `pro` et la clé de `secours` : à vérifier (à noter
ici une fois tranché, hors du dépôt pour la clé elle-même).

Clés SSH autorisées sur les hôtes : tous les `keys/*.pub` (`perso`, `pro`,
`android`, `github-actions`), posés en **exclusif** par `00-setup.yaml` :
une clé absente de `keys/` est retirée. `keys/perso.pub` sert aussi à
`tofu/pangolin` (`hcloud_ssh_key.keepassxc`, `user_data` de Pangolin).
Hors de cette pose, une clé remplacée reste autorisée tant qu'on ne l'a pas
retirée à la main : le compte principal de la Storage Box (`ssh_keys` en
`ignore_changes`, son `.ssh/authorized_keys` fait foi), le NAS et l'hôte
Proxmox (exclus de `00-setup.yaml`). Rien ne rejoue `00-setup.yaml` en CI :
`--limit` hôte par hôte, à la main.

## Réparation

### Clé age perso perdue (pas volée)

1. Déchiffrer avec une autre clé, `pro` ou `secours` :

   ```bash
   SOPS_AGE_KEY_FILE=/chemin/vers/secours.key sops decrypt secrets.sops.yaml > /dev/null && echo ok
   ```

   Que `SOPS_AGE_KEY_FILE` l'emporte sur `ageKeyFile` de `.sopsrc` : à vérifier.
2. Créer la nouvelle clé : `age-keygen -o ~/.age.key` (chmod 600). Noter la
   clé publique affichée.
3. Remplacer la ligne `# perso` dans les **deux** règles de `.sops.yaml`.
4. Rechiffrer la clé de données pour les nouveaux destinataires, puis la
   renouveler (consigne en tête de `.sops.yaml`) :

   ```bash
   sops updatekeys secrets.sops.yaml
   sops updatekeys ansible/secrets.sops.yaml
   sops rotate -i secrets.sops.yaml
   sops rotate -i ansible/secrets.sops.yaml
   ```

5. PR, merge. Vérifier : `sops decrypt secrets.sops.yaml > /dev/null`.

### Clé age volée, ou poste volé

Tout ce qui précède, **plus** : l'historique git garde les anciennes versions
chiffrées, que la clé volée ouvre toujours. `sops rotate` ne protège que
l'avenir. Il faut donc **changer les secrets eux-mêmes** : jetons cloud
(Hetzner, OVH, Cloudflare, Proxmox, S3, Uptime Kuma), mots de passe des
applis, `TF_VAR_state_encryption_passphrase`, identifiants Newt. Commencer
par ceux qui ouvrent le plus (jetons Hetzner et OVH, clés S3 des states).
`backup_passphrase` ne se change pas d'un coup : chaque dépôt Borg la
connaît (`borg key change-passphrase` dépôt par dépôt, à vérifier). Les
snapshots de la Storage Box ne sont pas effaçables par un hôte, mais le compte
principal Hetzner, lui, le peut : changer son mot de passe en priorité.

### Clé SSH perso perdue ou volée

1. Se connecter avec une autre clé autorisée (`pro`, `android`), ou par la
   console (Hetzner pour Pangolin et flip, Proxmox pour la VM docker, accès
   physique pour le Pi), avec le mot de passe de `sylvain`.
2. Remplacer `keys/perso.pub` par la nouvelle clé publique.
3. Rejouer la pose des clés, hôte par hôte, en vérifiant d'abord :

   ```bash
   cd ansible
   ansible-playbook 00-setup.yaml --limit pangolin --check --diff
   ansible-playbook 00-setup.yaml --limit pangolin
   ```

   `authorized_key` est exclusif : l'ancienne clé est retirée. Garder une
   session ouverte pendant ce temps.
4. `tofu/pangolin` : `mise run plan`. `keys/perso.pub` change
   `hcloud_ssh_key.keepassxc` ; si le plan veut **remplacer** le serveur
   Pangolin ou flip (attribut `ssh_keys`), ne pas forcer : `prevent_destroy`
   le bloquera, et la clé posée par Ansible suffit. À vérifier sur le plan.
5. Storage Box : `ansible/backup.yaml` envoie les clés avec la clé perso du
   compte principal (agent SSH). Mettre la nouvelle clé dans les clés du
   compte principal de la Storage Box (console Hetzner).
6. GitHub : retirer l'ancienne clé de son compte si elle y était.
7. `ssh_login_notify` alerte à chaque connexion SSH ; une clé se fait taire
   par son empreinte (`ssh_login_notify_ignored_fingerprints`), jamais par
   son commentaire. Mettre à jour la liste si elle contenait l'ancienne.

### Poste perdu

Les deux sections précédentes, plus : révoquer les sessions et jetons GitHub
du poste (`gh auth status`, paramètres GitHub), le client Pangolin du poste
(tableau de bord, Clients), les mots de passe enregistrés.

## Vérification

```bash
sops decrypt ansible/secrets.sops.yaml > /dev/null && echo sops ok
cd ansible && mise run ssh      # puis mise run ssh_flip, ssh sylvain@pangolin.sylvain.cloud
```

Le prochain run de `deploy-docker-app.yaml` passe (la clé `github-actions`
n'a pas changé).

## Prévention

- La clé `secours` existe pour ce cas : la garder hors ligne, et vérifier de
  temps en temps qu'elle déchiffre encore.
- Plusieurs clés SSH autorisées (`perso`, `pro`, `android`) : la perte d'une
  ne ferme pas la porte.
- Le mot de passe de `sylvain` (hash `host_user_password_hash`, généré par
  `mise run generate_password`) est ce qui ouvre la console : le garder dans
  le gestionnaire de mots de passe.
