# tofu/keepass_backup

Bucket S3 OVH du dépôt restic des bases KeePass, utilisé par le rôle Ansible `keepass_backup` des dotfiles
(`sylvainmetayer/dotfiles`, branche `feat/keepass-backup`). Aucune app du homelab ne s'en sert : la règle « Backups use
Borgmatic, not Restic » vise les apps du homelab, pas ce poste.

| Ressource | Rôle |
|---|---|
| `ovh_cloud_project_storage.keepass_backup` | Bucket `keepass-backup-sylvain`, EU-WEST-PAR (3 AZ), versionné, SSE-OMK, **Object Lock GOVERNANCE 30 jours** |
| `ovh_cloud_project_storage_object_bucket_lifecycle_configuration.keepass_backup` | Versions des verrous expirées après 1 jour, autres versions non courantes après 120 jours, multipart abandonnés après 7 jours |
| `ovh_cloud_project_user.writer` + credential + policy | Clé du poste : lecture, écriture, suppression des seuls `locks/*`, refus explicite sur le reste |
| `ovh_cloud_project_user.admin` + credential + policy | Clé d'administration, jamais sur disque : prune annuel, lecture des versions |

Object Lock ne s'active qu'à la création : le désactiver ou changer le nom du bucket recrée le bucket.

## Avant le premier apply : test sur un bucket jetable

La compatibilité de restic avec Object Lock chez OVH n'est pas encore vérifiée (les uploads vers un bucket verrouillé
exigent un en-tête de contrôle d'intégrité). Avant d'en dépendre : créer à la main un bucket jetable avec Object Lock
GOVERNANCE 1 jour, y faire `restic init`, deux `backup`, un `check`, un `restore`, puis avec une clé admin un
`forget --prune`. Vérifier aussi qu'un `DeleteObject` sur `data/*` avec la clé writer est bien refusé.

## Apply

```bash
cd tofu/keepass_backup
tofu init
tofu plan
tofu apply
tofu output bucket_owner_id   # ne doit être ni le writer ni l'admin (check owner_is_not_a_backup_user)
```

## Brancher le poste

Copier les valeurs dans le sops des dotfiles (`host_vars/home.sops.yaml`, clé `keepass_backup_restic`) :

```bash
tofu output -raw restic_repository      # repository
tofu output -raw writer_access_key      # access_key_id
tofu output -raw writer_secret_key      # secret_access_key
```

Le mot de passe du dépôt (`password`) est généré par KeePassXC. Il vit dans le sops des dotfiles **et sur papier** :
pas seulement dans KeePassXC, qui est justement ce que ce bucket sauvegarde. Puis, sur le poste : `ansible-playbook
playbook/setup-home.yaml --tags keepass_backup`, `keepass-backup init`, `keepass-backup run`, `keepass-backup check`.

Ranger `tofu output -raw admin_access_key` et `admin_secret_key` dans KeePassXC (entrée « Sauvegarde KeePass / restic
OVH admin »). Si la base est perdue, la restauration reste possible avec la clé writer (lecture), qui est dans le sops.

## Rétention, une fois par an, avec la clé admin

```bash
export AWS_ACCESS_KEY_ID=<admin> AWS_SECRET_ACCESS_KEY=<admin> RESTIC_REPOSITORY=<repository> RESTIC_PASSWORD_FILE=<fichier>
restic forget --tag keepass --keep-within 1y --keep-monthly 24 --keep-yearly unlimited --prune
```

Les objets supprimés deviennent des versions non courantes, détruites par le cycle de vie 120 jours plus tard (jamais
avant la fin de leur rétention Object Lock).

## Restaurer un objet écrasé

Avec la clé admin : `aws s3api list-object-versions --bucket keepass-backup-sylvain --prefix <chemin>` puis
`aws s3api get-object --version-id <id>`, endpoint `https://s3.eu-west-par.io.cloud.ovh.net`.
