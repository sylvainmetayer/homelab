# Mises à jour de l'hôte Proxmox et du NAS (UGOS)

Procédure, pas un incident. Ni l'hôte Proxmox VE ni le NAS n'ont de mises à
jour automatiques, et ce n'est pas un oubli : un paquet `pve-*`, `qemu-server`
ou un noyau se met à jour VM arrêtées, une mise à jour d'UGOS redémarre le
NAS sous la VM docker, sous Jellyfin et sous les sauvegardes vzdump. Le rôle
`update_notify` prévient, Sylvain applique.

## Ce qui prévient

`update-notify.timer` (rôle `update_notify`), le lundi vers 08:00, publie sur
le topic `scripts` de ntfy et pousse à un moniteur Uptime Kuma par hôte
(`tofu/pangolin_config/cron_updates.tf`, intervalle de 15 jours) :

| Hôte | Playbook | Message ntfy | Moniteur |
|---|---|---|---|
| Proxmox (`pve`) | `pve.yml`, mode `apt` | chaque lundi où quelque chose attend : `pve : N mise(s) à jour, dont S de sécurité`, la sécurité listée d'abord, puis Proxmox et noyaux, puis le reste ; priorité haute dès que `S > 0`. Aussi `pve : redémarrage en attente` quand un noyau plus récent que celui qui tourne est installé | « Mises à jour Proxmox » |
| NAS (`nas`) | `nas.yml`, mode `ugos` | le premier lundi de chaque mois : un rappel avec la version d'UGOS installée ; priorité haute `UGOS mis à jour, X → Y` dès que la version a changé | « Mises à jour NAS » |

Côté Proxmox, rien n'est installé : `apt-get update` puis une simulation
(`apt-get -s dist-upgrade`). Côté NAS, le script ne sait pas si une mise à
jour attend : UGOS n'a pas d'apt, et ni son interface (API à session, mot de
passe chiffré, double authentification possible) ni Ugreen (aucun flux de
versions public) ne le disent sans compte. Le rappel mensuel est le repli
assumé : il donne la version installée, à comparer dans l'interface.

Un moniteur rouge veut dire que le vérificateur ne passe plus ou échoue
(message du push) : `apt-get update en échec` (miroir, verrou des listes
tenu par `pve-daily-update`), `publication ntfy en échec`, `OS_VERSION
absent`, ou aucun battement (hôte éteint deux lundis, timer arrêté, unités
effacées par une réinitialisation d'UGOS). Diagnostic sur l'hôte :

```bash
systemctl status update-notify.timer update-notify.service
journalctl -u update-notify.service -n 50 --no-pager
systemctl start update-notify.service   # un passage tout de suite
```

Unités absentes : rejouer le playbook de l'hôte (`--tags update_notify`).

## Proxmox VE

Une demi-heure, en soirée hors du job vzdump de 21:00 (`tofu/proxmox/backup.tf`)
et hors de la nuit (borgmatic de la VM docker, `pve-daily-update`). Pendant
le redémarrage, toutes les applis de la VM docker tombent (moniteurs Uptime
Kuma rouges, attendu) et la CI ne joint plus la maison (elle passe par le
LXC newt) : ne rien merger qui déploie pendant ce temps.

### Avant

1. Lire la liste du message ntfy, puis sur l'hôte :
   ```bash
   ssh root@192.168.1.26
   apt update && apt list --upgradable
   pveversion -v | head -5
   ```
   Un saut de version mineure de `pve-manager` ou de `proxmox-kernel-*` :
   lire les notes de version de Proxmox VE (« Known issues ») avant. Une
   version majeure (Proxmox 9 → 10) n'est **pas** cette procédure : elle a
   son guide de migration (`pveNtoN+1` et son vérificateur).
2. Une sauvegarde fraîche des deux guests, sur le NAS, en plus de celle de
   21:00 :
   ```bash
   qm list && pct list               # ids de la VM docker et du LXC newt
   vzdump <id VM docker> <id LXC newt> --storage nas-backup --mode snapshot --compress zstd
   ```
   Le storage garde 2 archives par guest (`vzdump_keep_last`) : celle-ci
   pousse dehors la plus ancienne. Le NAS doit être allumé et `nas-backup`
   actif (`pvesm status`).

### Appliquer

1. Toujours `full-upgrade`, jamais `apt upgrade` (Proxmox ajoute et retire
   des paquets d'une version à l'autre ; `upgrade` laisse l'hôte entre deux) :
   ```bash
   apt full-upgrade
   ```
   Relire ce qu'apt propose de **retirer** : `proxmox-ve` ou `pve-manager`
   dans la liste, c'est un dépôt mal réglé, répondre non.
2. Sans noyau ni `pve-qemu-kvm` dans la liste : pas de redémarrage. Les
   démons `pve*` sont redémarrés par leurs paquets. Passer à « Après ».
3. Avec `pve-qemu-kvm` seul : la VM docker tourne sur l'ancien QEMU tant
   qu'elle n'est pas arrêtée puis relancée (un `reboot` dans la VM ne suffit
   pas) : `qm shutdown <id> --timeout 300 && qm start <id>`.
4. Avec un noyau : arrêter les guests dans l'ordre, la VM docker d'abord (ses
   applis et son montage NFS), le LXC newt en dernier (c'est lui qui donne
   l'accès distant), puis redémarrer l'hôte :
   ```bash
   qm shutdown <id VM docker> --timeout 300   # arrêt propre par l'agent QEMU
   pct shutdown <id LXC newt> --timeout 60
   reboot
   ```
   Au démarrage, `onboot: 1` relance les deux (le LXC en `order=3`, une
   minute d'attente, `tofu/proxmox/proxmox_newt_lxc.tf`).

### Après

```bash
pveversion                     # running kernel = le noyau installé
qm list && pct list            # VM docker et LXC newt « running »
pvesm status                   # nas-backup actif
apt autoremove --purge         # vieux noyaux (garder le courant et le précédent)
systemctl start update-notify.service && journalctl -u update-notify.service -n 5 --no-pager
```

Puis : les moniteurs Uptime Kuma reviennent au vert (quelques minutes, le
temps des `dc@`), l'agent Beszel `pve` remonte, et sur la VM docker
`findmnt /mnt/nas/apps` (montage NFS du NAS, rôle `nas_storage`). Le dernier
`update-notify` ne publie plus rien sur ntfy (ou seulement ce qui reste) et
pousse « à jour » à son moniteur.

En cas de problème au démarrage, le noyau précédent reste dans le menu GRUB
(console de l'hôte) ; une VM docker qui ne repart pas se restaure depuis la
sauvegarde vzdump faite avant (`qmrestore`, interface de Proxmox > storage
`nas-backup`).

## NAS Ugreen (UGOS Pro)

Le NAS redémarre pendant la mise à jour (une dizaine de minutes). Pendant
ce temps : Jellyfin et l'interface d'UGOS tombent, la VM docker attend son
montage NFS (`hard` : les applis qui y ont leurs données se figent, puis
repartent seules ; `nginx_demo` aujourd'hui), le site Pangolin `nas` est
hors ligne. Éviter 21:00-22:00 (vzdump vers le NAS) et 02:30 (borgmatic du
NAS).

### Avant

1. Panneau de configuration > Mise à jour et restauration : la version
   proposée et ses notes. Une version 1.x → 2.x, ou des notes qui touchent
   Docker, NFS ou le nginx de l'interface : attendre quelques jours les
   retours (forums, mariushosting.com).
2. Un instantané des dossiers partagés `docker` (composes, configuration et
   base de Jellyfin, borgmatic, certificats de `nas_proxy`) et `media`, dans
   Gestionnaire de stockage > Instantanés. La sauvegarde borg de Jellyfin
   (02:30) couvre sa configuration, pas les médias.
3. Vérifier que rien ne tourne : pas de vzdump en cours (interface Proxmox,
   Tâches), `ssh sylvain@192.168.1.137 systemctl is-active borgmatic.service`
   → `inactive`.

### Appliquer

Mettre à jour dans l'interface, attendre le redémarrage, se reconnecter.

### Après

1. Rejouer le playbook, depuis `ansible/` : une mise à jour d'UGOS peut
   recocher sa redirection HTTPS (le nginx d'UGOS reprend alors le 443 de
   l'hôte), réécrire `/etc/nfs.json` ou effacer ce qui est posé dans `/etc`
   (unités `dc@`, timers). Le playbook repose tout et vérifie le 443 :
   ```bash
   ansible-playbook nas.yml --check --diff   # relire
   ansible-playbook nas.yml
   ```
   Il échoue en le disant si le 443 de l'hôte est tenu par nginx : décocher
   « rediriger HTTP/HTTPS vers le port HTTPS de l'interface » dans l'interface
   d'UGOS, le relais `nas-proxy-443` reprend le port dans la minute
   (`docs/architecture.md`, Jellyfin et l'interface d'UGOS). Si c'est l'inverse
   (le relais a pris le 443 avant nginx et l'interface d'UGOS ne répond
   plus) : en SSH, `docker stop nas-proxy-443`, redémarrer nginx, décocher la
   case, `docker start nas-proxy-443`.
2. Vérifier : `https://media.sylvain.cloud` et `https://nas.sylvain.cloud`
   sans port en LAN, `showmount -e 192.168.1.137` (exports `/volume1/...`
   vers la VM docker et l'hôte Proxmox), le moniteur « Certificats NAS » et
   l'agent Beszel `nas` au vert, `findmnt /mnt/nas/apps` sur la VM docker.
3. Au lundi suivant, `update-notify` publie `UGOS mis à jour, X → Y`
   (priorité haute) : c'est le rappel de ce point 1 si on l'a sauté. Pour
   l'avoir tout de suite : `sudo systemctl start update-notify.service`.

## Prévention

- Ne pas ajouter d'`unattended-upgrades` sur l'hôte Proxmox : il
  installerait `pve-*` ou un noyau VM allumées, sans redémarrage, et masquerait
  l'alerte.
- Le moniteur de chaque vérificateur tolère un lundi manqué, pas deux : un
  hôte éteint plus de deux semaines le met au rouge, attendu.
