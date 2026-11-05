# Le Raspberry Pi (ou son SSD) est mort

Le Pi (192.168.1.96) fait tourner Immich (avec Immich Swipe et Selfie
Timelapse) et le premier Blocky. Il est volontairement hors de Proxmox
([ADR 0020](../adr/0020-garder-le-raspberry-pi-pour-immich.md)) : sa seule
sauvegarde est **Borg** (`backup/pi/immich`, chaque nuit à 01:00). Pas de
vzdump, pas d'image.

## Symptôme

- `photos.sylvain.cloud` répond 503, le moniteur Immich est rouge, le Newt du
  site `pi` est hors ligne.
- Moniteur « DNS Raspberry Pi » rouge : le LXC répond encore, les clients
  basculent sur lui, rien d'urgent ([dns-blocky.md](dns-blocky.md)).
- Le Pi ne répond plus au ping ; `mise run ssh_pi` échoue.

## Diagnostic

1. Courant, câble, voyants. Brancher écran et clavier : le Pi démarre-t-il ?
2. Le SSD : un NVMe derrière un pont USB (Beszel ne remonte peut-être pas son
   S.M.A.R.T., `host_vars/pi`). Un Pi qui boote sur un autre SSD de test
   dit si c'est le Pi ou le disque.
3. **Les photos prises depuis la dernière sauvegarde de 01:00 ne sont que sur
   les téléphones.** Ne rien supprimer sur les téléphones avant le premier
   passage de borgmatic après la restauration.
4. Le dépôt Borg est-il intact ? Dernière archive récente, moniteur « Backup
   Immich » vert avant la panne ; sinon, lire
   [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md).

## Réparation

1. **Système** : Raspberry Pi OS (Debian 13, `docs/conventions/ansible.md`) sur
   le SSD avec l'outil officiel Raspberry Pi Imager : nom d'hôte `pi`, compte
   `sylvain`, clé SSH. Version exacte de l'image, démarrage sur USB et
   réglages d'usine : à vérifier (le Pi est « à la main », hors Tofu).
2. **Réseau** : IP `192.168.1.96`. Le bail est réservé dans la Bbox, par
   adresse MAC : un **nouveau Pi a une nouvelle MAC**, mettre la réservation à
   jour ([bbox-remplacee.md](bbox-remplacee.md)). C'est l'IP que le DHCP
   annonce comme DNS et que Blocky publie ; Immich et l'accès `pi.internal` la
   visent aussi.
3. **Clé d'hôte** : à lire sur le Pi (écran et clavier), jamais par
   `ssh-keyscan` ; remplacer la ligne `pi,pi.internal,…` d'`ansible/known_hosts`
   par PR ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)). La CI lit ce
   fichier.
4. **Base et clé de sauvegarde**, depuis `ansible/`, `--check --diff` avant :

   ```bash
   ansible-playbook 00-setup.yaml --limit pi
   ansible-playbook pi.yml --tags setup    # Docker, security, borgmatic, newt
   ansible-playbook backup.yaml            # autorise la nouvelle clé chez backup-pi
   ansible-playbook pi.yml --tags backup   # /etc/borgmatic.d/immich.yaml
   ```

   (même méthode que [reconstruction-pangolin.md](reconstruction-pangolin.md),
   étapes 4 et 5 ; que `--tags backup` pose bien la config d'Immich : à vérifier.)
   Le Newt du site `pi` reprend ses identifiants de SOPS
   (`newt_pi_client_id`) : le site Pangolin n'est pas recréé.
5. **Restaurer avant de lancer Immich**, en root sur le Pi :

   ```bash
   borgmatic=/root/.local/bin/borgmatic
   config=/etc/borgmatic.d/immich.yaml
   $borgmatic list --config $config
   mkdir -p /root/restore/immich
   $borgmatic extract --config $config --archive latest --destination /root/restore/immich
   mkdir -p /opt/apps/immich
   cp -a /root/restore/immich/opt/apps/immich/. /opt/apps/immich/
   ```

   Le dossier `library` (les photos) pèse ce que pèse la photothèque : `borg
   info` donne la taille, le disque du Pi doit l'accueillir deux fois pendant
   la copie.
6. **La base** : la démarrer seule, puis rejouer le dump, Immich arrêté
   (sinon il migre pendant le rejeu) :

   ```bash
   cd /opt/apps/immich && docker compose up -d database
   $borgmatic restore --config $config --archive latest
   ```

   Si le `pg_restore` de l'hôte refuse le dump, rejouer avec celui du
   conteneur, comme pour [healthlog.md](healthlog.md#restauration-depuis-borg).
7. **Le reste**, comme au déploiement normal :

   ```bash
   ansible-playbook pi.yml --check --diff
   ansible-playbook pi.yml
   ```

   Blocky revient avec le rôle (`--tags blocky` seul si on ne veut que lui).
   Un redémarrage du Pi applique le réglage mémoire du noyau
   (`host_vars/pi`).

## Vérification

- `docker ps` sur le Pi : tout `Up` ; `https://photos.sylvain.cloud` répond ;
  la photothèque a ses photos et ses albums (la CI ne le contrôle que sur la
  base, [restore-test](../../.github/restore-test/README.md)).
- Le site `pi` est en ligne dans Pangolin ; `dig +short @192.168.1.96 example.com`
  répond ; moniteur « DNS Raspberry Pi » vert.
- L'appli mobile renvoie ses photos manquantes ; la sauvegarde de 01:00
  réussit (moniteur « Backup Immich »), et seulement alors les téléphones
  peuvent être allégés.
- Immich Swipe : la clé d'API vit dans la base d'Immich, vérifier qu'elle
  marche (sinon la refaire : [immich-swipe.md](immich-swipe.md)).

## Prévention

- Garder `backup/pi/immich` éprouvé : le test de restauration de la CI le
  rejoue le 1er et le 15 du mois (base et échantillon de fichiers, pas la
  photothèque entière).
- La photothèque n'a qu'une copie hors du Pi (Borg). Le Pi n'est pas dans
  vzdump et ne le sera pas (ADR 0020) ; la durée d'une restauration complète
  n'a pas été mesurée : à faire une fois, sur un SSD de rechange.
