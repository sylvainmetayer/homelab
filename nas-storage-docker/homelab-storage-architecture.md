# Architecture stockage/compute — Ugreen DXP2800 + Proxmox N100

Résumé des décisions prises et de la mise en place, pour référence.

## Principe général

- **NAS Ugreen DXP2800** = stockage uniquement.
- **VM Proxmox (N100)** = compute pur, jetable/reconstructible à tout moment.
- Deux protocoles selon la nature de la donnée :
  - **NFS** pour tout ce qui est fichiers (config, media, uploads) — un export global, un sous-dossier par appli.
  - **iSCSI + LVM** pour tout ce qui est bases de données — un disque virtuel par service, backé par du bloc, pas de partage de fichiers.
- **Terraform** provisionne la VM et ses disques (déclaratif, infra).
- **Ansible** configure l'intérieur de la VM et déploie les stacks Docker Compose (config, applicatif).
- **Sauvegarde** : un seul mécanisme, les snapshots Btrfs planifiés côté NAS (couvrent fichiers NFS et LUN iSCSI). Proxmox Backup Server reste en bonus optionnel pour le compute, pas pour les données.

Objectif final : la VM ne contient aucun état. `docker compose up` sur une VM neuve + réattachement des volumes NFS/iSCSI = restauration complète.

---

## 1. Stockage fichier — NFS (config, media, appdata)

NAS en NFSv3 uniquement (pas de v4 sur ce modèle). Un seul export global, sous-dossiers par appli — pas besoin d'un export dédié par service, `mountd` résout les sous-chemins d'un export existant même en v3.

### Côté NAS (une fois)
- Panneau de contrôle → Dossiers partagés → créer `/volume1/apps` (ou réutiliser l'existant).
- Onglet NFS → règle pour l'IP de la VM, `rw`, `sync`, `no_root_squash` si les conteneurs tournent en root.
- Arborescence par appli :
  ```
  /volume1/apps/
    ├── nginx-html/
    ├── nextcloud/{config,data}
    └── vaultwarden/data
  ```

### Côté Docker Compose (dans la VM)
```yaml
volumes:
  app_data:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=192.168.1.137,nfsvers=3,rw,hard,tcp,rsize=1048576,wsize=1048576"
      device: "192.168.1.137:/volume1/apps/<service>"
```

Points d'attention NFSv3 :
- `hard` (pas `soft`) pour les données réelles — évite la corruption silencieuse sur coupure réseau. (`soft`/`ro` acceptable seulement pour du contenu statique en lecture seule, comme le `nginx-html` actuel.)
- Ouvrir le port 111 (portmapper) en plus du 2049 si un firewall existe entre VM et NAS — NFSv3 utilise des ports dynamiques pour `mountd`/`statd`/`lockd`.
- Pas de mapping d'identité (contrairement à v4) : aligner directement les `PUID`/`PGID` entre NAS et conteneurs.
- Jamais de fichiers de BDD sur un volume NFS — locking NLM peu fiable → voir section iSCSI.

---

## 2. Stockage bloc — iSCSI + LVM (bases de données, isolation par service)

### Pourquoi
NFS partage des fichiers ; une BDD veut un disque. Le bloc élimine le problème de locking à la racine — `fsync` et le verrouillage POSIX se comportent comme sur un disque local.

### Mise en place détaillée (une fois, côté NAS puis Proxmox)

Pas d'automatisation possible côté NAS : UGOS Pro n'a pas d'API publique stable (contrairement à Synology/TrueNAS), donc toute cette section se fait à la main, une seule fois.

#### 2.1 — Côté NAS : créer la target et le LUN

1. **Activer le service iSCSI** : Panneau de contrôle / Storage Manager → iSCSI → activer le service si ce n'est pas déjà fait.
2. **Créer une Target** — c'est le "point d'entrée" réseau, identifié par un IQN (`iqn.2004-04.com.ugreen:nas:docker-pool` par ex., généré automatiquement). Une target = une entité qu'un initiateur (Proxmox) découvre et à laquelle il se connecte.
   - Activer **CHAP** (utilisateur + mot de passe) sur la target. iSCSI n'a pas d'authentification native comme NFS (qui filtre par IP côté export) — sans CHAP, n'importe quelle machine du réseau qui connaît l'IQN peut monter le LUN en lecture/écriture. Le CHAP est le minimum pour un LUN qui va contenir des BDD.
   - Si l'interface le permet, restreindre l'accès réseau à la target à la seule IP du nœud Proxmox (N100).
3. **Créer un LUN** rattaché à cette target :
   - Choisir le pool de stockage qui l'héberge (le volume RAID/Btrfs existant du DXP2800).
   - **Thin provisioning** recommandé — n'alloue l'espace qu'à l'usage réel, important sur un NAS 2 baies qui héberge aussi les exports NFS sur le même pool.
   - Taille : généreuse mais pas au point de saturer le pool (le LVM Proxmox pourra redimensionner la LV du LUN plus tard si besoin, mais agrandir le LUN lui-même côté NAS reste une opération manuelle).
   - Un seul LUN par target suffit pour ce cas d'usage (`docker-pool`) — inutile de multiplier les targets, la granularité par service se fait plus haut, côté LVM/Terraform.
4. Vérifier que le port **3260** (port standard iSCSI) est joignable depuis l'IP du Proxmox — pare-feu UGOS si activé.

#### 2.2 — Côté Proxmox : déclarer le storage iSCSI, puis LVM par-dessus

**Via l'interface web** (recommandé pour cette étape ponctuelle, moins sujette aux erreurs de syntaxe CLI) :

1. Datacenter → Storage → Add → **iSCSI** :
   - Portal = IP du NAS (`192.168.1.137`)
   - Target = sélectionner l'IQN découvert automatiquement dans la liste déroulante
   - Renseigner les identifiants CHAP si activés côté NAS
   - **Content = None** — ce storage brut ne doit pas stocker d'images directement, il sert uniquement de base au layer LVM suivant.
   - Proxmox gère lui-même le cycle de vie de la session iSCSI (login/logout) à partir de cette déclaration — ne pas faire de `iscsiadm login` manuel en parallèle, ça créerait un conflit de session.
2. Vérifier que le LUN est bien vu : `pvesm status` (le storage iSCSI apparaît) et `pvesm list nas-iscsi` (liste le/les LUN détecté(s), avec leur identifiant exact — à noter pour l'étape suivante).
3. Datacenter → Storage → Add → **LVM** :
   - Base storage = le storage iSCSI créé à l'étape 1 (`nas-iscsi`)
   - Base volume = le LUN listé par `pvesm list` à l'étape précédente
   - VG name = `vg-iscsi`
   - Shared = oui (pas utile avec un seul nœud aujourd'hui, mais ne coûte rien et évite d'y revenir si un second nœud Proxmox est ajouté un jour)

Proxmox exécute alors `pvcreate`/`vgcreate` sur le LUN pour en faire un groupe de volumes LVM.

**Équivalent CLI** (indicatif — vérifier l'identifiant exact du LUN via `pvesm list nas-iscsi` avant de le référencer dans `--base`, le format exact dépend de la sortie) :
```bash
pvesm add iscsi nas-iscsi --portal 192.168.1.137 --target iqn.<...>:docker-pool --content none
pvesm list nas-iscsi   # note l'identifiant exact du LUN affiché
pvesm add lvm iscsi-lvm --base nas-iscsi:<lun-id> --vgname vg-iscsi --shared 1
```

Résultat : un groupe de volumes (`iscsi-lvm`) sur lequel Proxmox peut découper une LV **par service** — c'est la granularité "un volume par appli" sans jamais recréer de LUN côté NAS. C'est ce storage `iscsi-lvm` qui est référencé dans le bloc Terraform de la section 3 (`datastore_id = "iscsi-lvm"`).

---

## 3. Provisioning — Terraform (VM + disques par service)

Provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox). Terraform gère la VM et l'attachement des disques ; il ne gère pas la définition du storage `iscsi-lvm` (étape one-shot ci-dessus, pas de ressource Terraform mature pour ça).

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://proxmox.local:8006/"
  api_token = var.proxmox_api_token
  insecure  = true
}

variable "services" {
  description = "Un disque iSCSI/LVM par service nécessitant une BDD isolée"
  type = map(object({
    size_gb = number
  }))
  default = {
    postgres_nextcloud   = { size_gb = 20 }
    postgres_vaultwarden = { size_gb = 5 }
    postgres_authelia    = { size_gb = 5 }
  }
}

locals {
  # scsi0 = disque OS, scsi1+ = un par service
  service_index = { for idx, name in sort(keys(var.services)) : name => idx + 1 }
}

resource "proxmox_virtual_environment_vm" "docker_host" {
  name      = "docker-host"
  node_name = "pve"

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
  }

  dynamic "disk" {
    for_each = var.services
    iterator = svc
    content {
      datastore_id = "iscsi-lvm"
      interface    = "scsi${local.service_index[svc.key]}"
      size         = svc.value.size_gb
      file_format  = "raw"
    }
  }

  agent {
    enabled = true # nécessaire pour les backups PBS cohérents (fsfreeze)
  }
}
```

Ajouter un service = ajouter une entrée à `var.services` + `terraform apply`. Le disque apparaît dans la VM en `/dev/sdX`, prêt à être formaté par Ansible.

---

## 4. Configuration — Ansible (in-VM)

Playbook complet dans `playbook.yml` (même dossier) : installe `nfs-common`/Docker, formate et monte chaque disque de service (idempotent — ne reformate jamais un disque déjà formaté, donc sûr à relancer), puis déploie les stacks Compose.

Points notables du playbook :
- `community.general.filesystem` ne reformate pas un disque déjà formaté par défaut — relancer le playbook après ajout d'un nouveau service (nouveau disque Terraform) ne touche pas aux volumes existants.
- Les chemins `/dev/sdX` du playbook sont indicatifs — pas garantis stables d'un reboot à l'autre ; pour une conf durable, monter par UUID (`blkid`) une fois le premier formatage fait.
- Les fichiers de config des applis (pas la BDD) continuent de passer par le volume NFS `driver_opts` défini dans chaque `docker-compose.yml`, comme en section 1 — le playbook ne les monte pas explicitement, c'est le driver Docker qui s'en charge au démarrage du conteneur.

---

## 5. Backup — un seul mécanisme, côté NAS

Principe : NFS et iSCSI vivent tous les deux sur le même pool Btrfs du NAS — le LUN iSCSI n'est qu'un fichier thin-provisionné dans ce pool, au même titre que l'export `apps/`. La VM ne contenant aucun état, la sauvegarde se réduit à **un seul pipeline, entièrement côté NAS**, plutôt qu'à croiser un état Proxmox et un état NAS séparés.

| Étape | Mécanisme | Couvre |
|---|---|---|
| Snapshot | Snapshots Btrfs planifiés sur le pool NAS (export `apps/` + volume hébergeant le LUN `docker-pool`) | Fichiers et disques de BDD, même planification, même rétention |
| Cohérence BDD | Aucune action requise | Le snapshot Btrfs est un copy-on-write atomique → image crash-consistante, rejouable via le WAL du moteur (Postgres/MySQL) au redémarrage — même principe qu'un snapshot EBS + replay WAL chez un cloud provider |
| Hors-site | Un seul job de réplication à partir des mêmes snapshots (`btrfs send/receive` vers un NAS distant, ou `restic`/`rclone`) | Évite que le NAS local soit un point de défaillance unique |

Point de contrôle quotidien unique : *le dernier snapshot NAS existe et a été répliqué hors-site*.

### Filets optionnels (pas des points à surveiller séparément)

- **Proxmox Backup Server** : à garder en bonus pour restaurer vite le *compute* (OS, config VM) — ce n'est plus la source de vérité pour les données, puisque la VM est jetable et que la perdre/recréer ne perd aucune donnée tant que NFS/iSCSI sont intacts côté NAS. Pas besoin de `qemu-guest-agent`/fsfreeze pour la cohérence des disques de BDD, déjà garantie par l'atomicité du snapshot Btrfs + WAL.
- **Dump logique (`pg_dump`/`mysqldump`)** : utile pour une restauration indépendante de la version/structure du moteur, mais à écrire **dans un dossier de l'export NFS déjà snapshotté** — il est alors capturé automatiquement par le même job Btrfs, sans planification ni vérification séparée.

---

## 6. Checklist de mise en place (ordre d'exécution)

1. NAS : créer l'export NFS `/volume1/apps` + règle NFSv3 pour l'IP de la VM.
2. NAS : créer la target/LUN iSCSI unique (`docker-pool`).
3. Proxmox : `pvesm add iscsi` + `pvesm add lvm` sur le LUN.
4. Terraform : provisionner/mettre à jour la VM avec un disque par service dans `var.services`.
5. Ansible : formater + monter les nouveaux disques, installer `nfs-common`.
6. Ansible/Compose : déployer les stacks (NFS pour fichiers, bind mount local pour BDD).
7. NAS : activer les snapshots Btrfs planifiés sur le pool hébergeant `apps/` + LUN — mécanisme de sauvegarde principal et unique.
8. NAS : configurer la réplication hors-site à partir de ces mêmes snapshots (`btrfs send/receive`, `restic`/`rclone`).
9. (Optionnel) Cron : dump logique des BDD écrit dans l'export NFS, pour une restauration indépendante du moteur.
10. (Optionnel) PBS : en bonus pour la résilience du compute (OS/config VM), pas pour les données.
