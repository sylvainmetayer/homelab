# Infra 2026

## Deps

- mise install
- uv sync

## Packer

Une image Packer est disponible pour déployer Pangolin Zero Trust sur Hetzner :

```bash
# Construire l'image (nécessite variable d'environnement HCLOUD_TOKEN)
mise run packer-build
```

L'image inclut :
- Docker et Docker Compose
- Pangolin installer pré-téléchargé dans `/opt/pangolin`
- Configuration de hardening (SSH, fail2ban, UFW, sysctl)
- cloud-init nettoyé pour permettre une reconfiguration au déploiement

## Notes

- [Donner accès en lecture seulement au socket docker](https://www.it-connect.fr/docker-comment-ameliorer-la-securite-avec-un-docker-socket-proxy/)
- pour que ça marche, pangolin newt doit être dans le même network docker que les conteneurs
- https://github.com/orgs/fosrl/discussions/402#discussion-8123152
- https://pangolin.net/blog/posts/blueprints


## Restauration

Pour restaurer une sauvegarde avec borgmatic (à améliorer), exemple avec betisier

```bash
sudo -s # root obligatoire
cd /opt/apps/betisier
borgmatic extract --archive latest --repo betisier-s3 -v 2 --strip-components all --path /opt/apps/betisier
mv betisier/* .
rm -rf betisier
# pour la partie DB
rm -rf borgmatic
# En tant qu'user
systemctl start dc@betisier --user
# pour le container db soit up
# retour root
sudo -s
borgmatic restore --archive latest --repo betisier-s3
```

## Migration du state Terraform/OpenTofu vers un bucket S3 OVH

Le state OpenTofu de chaque stack (`tofu/dns`, `tofu/pangolin`, `tofu/pangolin_config`,
`tofu/proxmox`) est actuellement stocké dans le bucket S3 Hetzner `homelab-state`
(voir `backend.tf` de chaque stack). Pour migrer vers un bucket S3 OVH :

1. **Créer le bucket de state via le stack `tofu/s3_state`** (volontairement séparé
   des autres stacks : un stack ne doit pas gérer le bucket qui contient son propre
   state). Ce stack utilise la ressource native `ovh_cloud_project_storage` du
   provider `ovh` (et non le provider `aws`) pour créer le bucket Object Storage
   `homelab-tf-state-sylvain`.
   - Renseigner `OVH_CLOUD_PROJECT_ID` (l'ID du projet Public Cloud OVH) dans
     `secrets.sops.yaml` (`sops secrets.sops.yaml`) — lu par `tofu/s3_state/secrets.tf`.
   - Appliquer le stack :
     ```bash
     cd tofu/s3_state
     tofu init
     tofu apply
     ```
   - Créer ensuite un utilisateur S3 dédié (Public Cloud > Object Storage >
     Utilisateurs) sur ce bucket pour obtenir une paire `access_key`/`secret_key`.
     Ce sont des identifiants S3, différents de `OVH_APPLICATION_KEY/SECRET`
     (clés API OVH utilisées par le provider `ovh` pour la gestion DNS et pour
     créer le bucket lui-même).

2. **Ajouter les secrets** `OVH_S3_ACCESS_KEY` et `OVH_S3_SECRET_KEY` dans
   `secrets.sops.yaml` (`sops secrets.sops.yaml`) — utilisés uniquement pour la
   migration ci-dessous (backend S3 des autres stacks).

3. **Mettre à jour `backend.tf`** de chaque stack en remplaçant l'endpoint Hetzner
   par l'endpoint OVH (garder la même clé `key` pour préserver le chemin du state) :
   ```hcl
   terraform {
     backend "s3" {
       endpoints = { s3 = "https://s3.eu-west-par.io.cloud.ovh.net" }
       bucket                      = "homelab-tf-state-sylvain"
       key                         = "homelab/pangolin.tfstate" # inchangé
       region                      = "eu-west-par"
       skip_region_validation      = true
       skip_credentials_validation = true
       use_path_style              = true
     }
   }
   ```

4. **Migrer chaque stack**, un par un, en passant explicitement les identifiants
   S3 OVH (les variables d'environnement `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
   injectées par `mise` correspondent aux clés Hetzner, pas OVH) :
   ```bash
   cd tofu/<stack>   # dns, pangolin, pangolin_config, proxmox
   tofu init -migrate-state -reconfigure \
     -backend-config="access_key=<ovh_s3_access_key>" \
     -backend-config="secret_key=<ovh_s3_secret_key>"
   # répondre "yes" à la question de migration du state
   tofu plan   # doit afficher "no changes" si la migration s'est bien passée
   ```

5. Une fois les 4 stacks migrés et vérifiés (`tofu plan` sans diff), le bucket
   Hetzner `homelab-state` peut être conservé comme filet de sécurité quelque temps
   avant suppression — `migrate-state` copie le state, il ne supprime pas la source.

⚠️ Migration à exécuter manuellement avec de vrais identifiants OVH : cette
opération modifie l'emplacement de vérité de l'infrastructure et n'est pas
automatisée dans ce dépôt.
