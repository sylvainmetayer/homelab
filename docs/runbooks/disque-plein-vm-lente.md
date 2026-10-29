# Disque plein, ou VM docker lente

La VM docker (Proxmox 300) a 3 cœurs, 12 Gio de RAM sans ballooning et un
disque de 190 Go sur le SSD M.2 SATA d'entrée de gamme de l'hôte. Son goulot est presque toujours le disque (I/O
wait), pas le CPU : l'usage CPU cumulé tourne autour de quelques pour cent.

## Symptôme

- Applis lentes, timeouts, moniteurs Uptime Kuma qui clignotent.
- Charge (`uptime`) élevée alors que le CPU est presque inactif.
- Erreurs `No space left on device` dans les journaux, conteneurs qui ne
  démarrent plus, sauvegardes en échec.

## Diagnostic

Des compteurs bon marché d'abord. **Jamais** `journalctl --since -30days` ni
un `find /` sur ce disque : la lecture seule suffit à faire grimper la charge.

```bash
cd ansible && mise run ssh
uptime
cat /proc/pressure/io          # avg10 élevé = processus qui attendent le disque
cat /proc/pressure/memory
cat /sys/block/vda/queue/rotational   # 1, mais trompeur : virtio-blk sur le SSD de l'hôte
free -m
df -h / /opt/apps
```

Par conteneur (cgroup v2, pilote systemd) :

```bash
docker stats --no-stream
id=$(docker inspect -f '{{.Id}}' <conteneur>)
cat /sys/fs/cgroup/system.slice/docker-$id.scope/memory.peak      # pic depuis le démarrage
cat /sys/fs/cgroup/system.slice/docker-$id.scope/memory.events    # oom, oom_kill, high, max
cat /sys/fs/cgroup/system.slice/docker-$id.scope/cpu.stat         # nr_throttled
sudo dmesg | grep -i "memory cgroup out of memory"
```

Un conteneur au plafond de son `mem_limit` n'est pas forcément tué : son
cache de pages est évincé et il martèle le disque. Un `oom_kill` qui monte
signale une boucle OOM (cas de gramps : 8 workers gunicorn sous 1 Gio).

Place disque :

```bash
docker system df
sudo du -xh --max-depth=1 /opt/apps | sort -h | tail
sudo du -xh --max-depth=1 /var/lib/docker | sort -h | tail
journalctl --disk-usage
```

## Réparation

- **Images obsolètes** (anciens digests après les montées Renovate) :
  `docker image prune -a` retire les images qu'aucun conteneur n'utilise.
  Sans risque pour les applis en place ; une appli arrêtée retéléchargera son
  image au prochain démarrage.
- **Journaux** : journald est borné à 500 Mo (`host_tuning`), les journaux
  Docker à 3 × 10 Mo par conteneur (`group_vars/all/geerlingguy.docker.yml`,
  seulement pour les conteneurs recréés depuis). Au besoin :
  `sudo journalctl --vacuum-size=200M`.
- **Données d'une appli qui gonflent** : traiter dans l'appli (corbeille
  Nextcloud, cache Immich, etc.), pas par `rm` dans `/opt/apps`.
- **Conteneur au plafond mémoire** : remonter son `mem_limit` à environ 2×
  le `memory.peak` mesuré, et ajouter `mem_reservation` ≈ le pic pour une
  base. Dans le `compose.yaml` du rôle, PR, merge (= déploiement).
- **Boucle OOM** : réduire le nombre de workers de l'image (variable
  d'environnement de l'appli) plutôt que d'augmenter la RAM.
- **Disque de la VM trop petit** : augmenter `docker_vm.disk_size` dans
  `tofu/proxmox/terraform.tfvars`, `mise run plan-proxmox`, puis
  `mise run apply-proxmox`. Agrandir ensuite la partition et le système de
  fichiers dans la VM : à vérifier (cloud-init le fait peut-être au
  redémarrage).

## Vérification

```bash
df -h /
cat /proc/pressure/io
docker stats --no-stream
```

La pression I/O redescend, les moniteurs restent UP.

## Prévention

La doctrine de limites ([conventions/resource-limits.md](../conventions/resource-limits.md)) :

- chaque service a un `mem_limit` ≈ 2× son pic mesuré, jamais en dessous ;
- les bases ont aussi `mem_reservation` ≈ le pic (protège leur cache) ;
- **pas de `cpus:`** sur les bases, redis/valkey et les services interactifs
  (un quota sous 1 cœur étrangle chaque rafale) ;
- seuls les traitements de fond (OCR, conversion, workers Celery/Sidekiq) ont
  `cpus: 2.00` + `cpu_shares: 512` ;
- vérifier le nombre de workers par défaut d'une image contre son plafond.
