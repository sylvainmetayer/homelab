# Rôle `pve_config_backup`

Sauvegarde Borg, chaque nuit à 01:00 (`borgmatic.timer` du rôle `borgmatic`),
de la configuration de l'hôte Proxmox (`pve.yml`) vers son sous-compte Storage
Box (`backup/pve/pve_config`, hors de la maison). Une seule tâche : le gabarit
partagé du rôle `borgmatic` (`tasks_from: app.yml`). Moniteur « Backup Proxmox
config » (`tofu/pangolin_config/backup_pve_config.tf`), dépôt testé par
`restore-test.yaml` (`.github/restore-test/apps.json`, table `tree`).

## Ce qui est sauvegardé

- **`/var/lib/pve-cluster/config.db`** : la base de pmxcfs, dont `/etc/pve`
  n'est que la vue FUSE (storages, `user.cfg`, `domains.cfg` et son realm
  OpenID, `token.cfg`, `shadow.cfg`, `tfa.cfg`, `jobs.cfg`, pare-feu,
  SDN, configs des invités, `priv/` : clé de la CA, `authkey`, ACME). Copiée
  à chaud par `VACUUM INTO` (base en WAL), jamais lue vivante ni par
  `sqlite_databases` de borgmatic (README du rôle `borgmatic`).
- `/etc/network/interfaces` (+ `interfaces.d/`), `/etc/hosts`,
  `/etc/hostname`, `/etc/resolv.conf` : écrits par l'installeur, régénérés
  par personne.

## Ce qui ne l'est pas, et pourquoi

- Les disques des invités : vzdump sur le NAS (`tofu/proxmox/backup.tf`).
- Ce qu'Ansible ou Tofu refont : `/etc/vzdump.conf` (`pve.yml`), sshd, dépôts
  apt, pare-feu de l'hôte, SDN (`pve_hardening`), agent Beszel, timers des
  autres rôles de `pve.yml`, invités et job vzdump (`tofu/proxmox`).
- `/etc/fstab`, `/etc/lvm`, `/boot` : propres au disque, faux sur une
  installation neuve.
- Les clés d'hôte SSH (`/etc/ssh`) : un hôte réinstallé en a de nouvelles
  (`docs/runbooks/cle-hote-ssh-changee.md`).

L'archive porte des secrets (jetons d'API, clé de la CA, empreintes des
mots de passe) : chiffrée par `backup_passphrase` comme les autres, son
sous-compte n'est lisible que par pve et, en lecture seule, par
`restore-test`. Pas le sous-compte d'un autre hôte : root de la VM docker
lirait alors de quoi prendre l'hyperviseur.

## Sur l'hôte

Le rôle `borgmatic` installe sur l'hôte Proxmox pipx, borg et les clients
`mariadb-client`/`postgresql-client` (inutiles ici, sans conflit avec les
paquets de Proxmox) ; il n'écrit pas `/root/.ssh/config`, qui est à Proxmox
(`borgmatic_ssh_config: false`, `host_vars/pve`). `pve.yml` saute les deux
rôles tant que la clé SOPS `backup_storage_box_subaccounts` n'a pas d'entrée
`pve`.

Mise en place (une fois, dans l'ordre) : sous-compte (`tofu/pangolin`),
entrée SOPS, `ansible-playbook pve.yml --tags setup` (clé de root),
`ansible-playbook backup.yaml`, puis `ansible-playbook pve.yml --tags
pve_config_backup`.

Restauration sur un hôte réinstallé : `docs/runbooks/hote-proxmox-mort.md`,
« Remettre la configuration de l'hôte ».
