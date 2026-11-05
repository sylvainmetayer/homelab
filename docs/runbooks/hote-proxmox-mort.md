# L'hôte Proxmox est mort

L'hôte (`pve`, 192.168.1.26, nœud `proxmox`) porte la VM docker (id 100) et
le LXC newt (id 200). Ce site de documentation est sur la VM docker : lire
cette page sur GitHub ou dans un clone local.

## Symptôme

- Toutes les applis de la VM docker tombent (503 ou page de maintenance de
  Pangolin), plus de ping sur 192.168.1.26, 216 et 200.
- Plus d'accès à la maison par le client Pangolin (le Newt du site
  `proxmox-lxc` est dans le LXC), la CI ne déploie plus ni docker ni pi.
- **ntfy, Beszel, VictoriaLogs, Homepage et cette doc sont sur la VM docker :
  les alertes ne viennent plus que de Telegram** (Uptime Kuma est chez PikaPods).

Ne tombent pas : Immich (Newt du Pi), Flip Planning, Pangolin, les sites
Cloudflare Pages. Le DNS tient : le Pi garde le second Blocky, les clients
basculent ([dns-blocky.md](dns-blocky.md)).

## Diagnostic

1. Le courant, le câble, l'écran de la machine (pas d'IPMI). Si elle
   redémarre : [proxmox-injoignable-apres-durcissement.md](proxmox-injoignable-apres-durcissement.md)
   d'abord, ce n'est peut-être qu'un pare-feu.
2. Le disque : le SSD M.2 SATA porte l'hôte et `local-lvm` (`host_vars/pve`).
   Un disque mort = installation neuve. Une carte mère morte avec un disque sain :
   essayer le disque dans une autre machine avant de tout refaire (à vérifier).
3. **Ne restaurer sur un nouvel hôte que si l'ancien ne peut plus se
   rallumer** : deux copies du LXC ou de la VM (même IP, mêmes identifiants
   Newt) se battraient.
4. Le NAS vit-il ? Les archives vzdump y sont (`/volume1/pve-backup`, une
   seule copie, [ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md)). Sinon : [disque-nas-mort.md](disque-nas-mort.md), et la VM se
   reconstruit depuis Borg (étape C).

## Réparation

### A. Réinstaller l'hôte

1. Proxmox VE depuis l'ISO officielle sur un disque assez grand (VM de 190 Gio,
   `tofu/proxmox/terraform.tfvars`), système de fichiers par défaut
   (LVM-thin `local-lvm` attendu : à vérifier). Nom du nœud **`proxmox`**,
   IP `192.168.1.26/24`, passerelle `192.168.1.254`.
2. Clés SSH : mettre les `keys/*.pub` utiles dans `/etc/pve/priv/authorized_keys`
   (console de l'hôte). Le certificat de `pve.sylvain.cloud` (ACME DNS-01 OVH)
   est un réglage de l'interface, absent du dépôt : à refaire à la main.
3. **Clé d'hôte** : la lire sur l'hôte (console), jamais par `ssh-keyscan`,
   et remplacer la ligne `pve,…` d'`ansible/known_hosts` par PR
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)). Les clés des invités
   restaurés ne changent pas.
4. Jeton d'API pour Tofu : en créer un (`PROXMOX_TOKEN` dans
   `secrets/secrets.sops.yaml`, [rotation-des-secrets.md](rotation-des-secrets.md),
   « Proxmox »). Les droits de l'ancien ne sont écrits nulle part : à noter cette
   fois.

### B. Restaurer depuis le NAS

1. Le storage : `pvesm add nfs nas-backup --server 192.168.1.137 --export
   /volume1/pve-backup --content backup --options vers=3` (valeurs de
   `tofu/proxmox/backup.tf` ; syntaxe de la doc Proxmox, à vérifier). Le NAS
   n'exporte qu'à l'IP 192.168.1.26 : une autre IP demande `nas_nfs_exports`
   et `nas.yml`.
2. Les archives : `ls /mnt/pve/nas-backup/dump/` (`vzdump-lxc-200-*`,
   `vzdump-qemu-100-*`). Prendre les plus récentes dont le `.log` est sans
   `ERROR:`.
3. **Le LXC d'abord** (petit, il rend le DNS redondant et l'accès distant) :

   ```bash
   pct restore 200 /mnt/pve/nas-backup/dump/<archive LXC> --storage local-lvm
   pct start 200
   ```

4. **Puis la VM** (190 Gio de disque : le test bimensuel ne fait que vérifier
   l'archive, la restauration complète n'a **jamais été essayée**, durée à vérifier) :

   ```bash
   qmrestore /mnt/pve/nas-backup/dump/<archive VM> 100 --storage local-lvm
   qm config 100 | grep -E 'cicustom|ide|net0|onboot'
   qm start 100
   ```

   Si le démarrage se plaint d'un volume `snippets` ou cloud-init manquant
   (fichiers de `tofu/proxmox` sur `local`) : `qm set 100 --delete cicustom`
   ou recréer les fichiers par Tofu (relire le plan) : à vérifier.
5. L'archive date de 21:00 au plus tard la veille : les données écrites depuis
   n'y sont pas. Pour une appli importante, remettre ensuite son dump Borg de
   01:00 ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)).

### C. NAS aussi perdu, ou VM douteuse

Pas d'archive : recréer la VM par Tofu (`mise run init-proxmox`, `plan-proxmox`,
relire, `apply-proxmox`), puis `ansible-playbook docker.yml` et chaque appli
depuis Borg, une à une (`backup/docker/<app>`). Long : tout est hors site, rien
n'est perdu, mais rien n'est rapide. Même chose si la VM est suspecte
([intrusion-premiere-heure.md](intrusion-premiere-heure.md)) : une archive
restaurée ramène aussi l'intrus.

### D. Remettre Tofu et Ansible d'accord

1. `tofu -chdir=tofu/proxmox plan` : stockage `nas-backup` (déjà créé) et
   job vzdump à recréer, jamais un `must be replaced` sur la VM ou le LXC (les
   invités restaurés sont retrouvés par leur id). Le storage créé à la main
   s'importe par la CLI (`tofu import`, identifiant à vérifier dans la doc du
   provider), le job se crée.
2. Depuis `ansible/`, avec `--check --diff` d'abord :
   `ansible-playbook pve.yml` (agent Beszel, `/etc/vzdump.conf`, test de
   restauration, avis de mises à jour, puis `pve_hardening` en dernier, une
   session root de secours ouverte), et `lxc.yml` (à la main) si le LXC doit être
   remis d'équerre.

## Vérification

- `qm list` et `pct list` : 100 et 200 `running` ; `pvesm status` :
  `nas-backup` actif.
- Sur le LXC : `systemctl status newt blocky` ; le site `proxmox-lxc` est en
  ligne dans Pangolin ; `dig +short @192.168.1.200 example.com` répond.
- Sur la VM : `systemctl --user list-units 'dc@*' --state=failed` vide ;
  moniteurs Uptime Kuma verts ; ntfy reçoit un message.
- Une sauvegarde à la main (`vzdump 100 200 --storage nas-backup --mode
  snapshot --compress zstd`) réussit, et le prochain run de 21:00 aussi.
- Un merge de test qui déploie passe (la CI joint la maison par le LXC).

## Prévention

- Ne garder qu'une copie des archives sur le NAS est un risque accepté (ADR 0026).
- Consigner les droits du jeton Proxmox et la configuration de l'ACME.
- Une restauration complète de la VM, essayée une fois, vaut mieux qu'une
  archive seulement vérifiée ([test-restauration-vm.md](test-restauration-vm.md)).
