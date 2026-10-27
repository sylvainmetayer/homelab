# Test de restauration des dépôts borg

`.github/workflows/restore-test.yaml` (le 1er et le 15 du mois à 10:00 UTC,
ou à la main) restaure la dernière archive de chaque dépôt de `apps.json` sur
un runner GitHub, loin des hôtes qui la produisent (issue #444). Pour chaque
dépôt (`.github/scripts/restore_test.py`) :

- la dernière archive doit dater de moins de 28 h (une nuit manquée
  suffit) : une sauvegarde qui ne tourne plus (un dump qui échoue chaque
  nuit, comme celui de Nextcloud en octobre 2026) laisse une vieille archive
  qui, elle, se restaure ;
- un échantillon de 20 fichiers (≤ 5 Mio) est extrait : borg vérifie chaque
  bloc qu'il déchiffre ;
- les dumps PostgreSQL (`pg_restore`) et MariaDB (`mariadb`) sont rejoués
  dans un conteneur jetable de l'image de la base du rôle (lue dans son
  `compose.yaml`), puis il doit rester au moins une table (sauf
  `allow_empty_databases`, voir plus bas) ;
- les copies SQLite (`/var/lib/borgmatic-sqlite/<dépôt>/`) passent
  `PRAGMA integrity_check`.

Les journaux d'un dépôt public sont publics : les commandes qui portent des
chemins de l'archive (`borg list`, `borg extract`) ou des lignes d'un dump
(`pg_restore`, `mariadb`) n'y montrent pas leurs arguments, et aucune commande
n'y montre sa sortie d'erreur (seule exception : la dernière ligne de
`borg list --json`, le message de borg quand le dépôt ne s'ouvre pas). Ni
journaux des conteneurs de base, ni détail d'`integrity_check`, ni traceback
Python (seulement le type de l'exception). Pour le détail d'un échec, rejouer
la commande depuis un poste.

Rien d'autre n'est téléchargé : immich ne coûte que la liste de l'archive,
le dump de sa base et l'échantillon.

Le dernier job pousse le résultat global sur le moniteur Uptime Kuma
« Restore test » (`tofu/pangolin_config/restore_test_monitor.tf`, 20 jours :
le provider plafonne un push à 24). Le détail par app est dans le run. Un run
manuel limité à quelques apps ne pousse rien.

## Accès et secrets

Environnement GitHub `restore-test`, lisible depuis `main` seulement
(`tofu/github/restore_test_secrets.tf`), distinct de `production` pour que
ce workflow ne puisse lire ni la clé age ni la clé de déploiement :

- `RESTORE_TEST_SSH_KEY`, `RESTORE_TEST_STORAGE_BOX` : sous-compte Storage
  Box `restore-test` (`tofu/pangolin/storage_box.tf`), **en lecture seule**,
  dossier racine `backup/` : il lit les dépôts `backup/<hôte>/<dépôt>` de
  tous les hôtes et ne peut rien effacer. borg 1.x pose un verrou même pour
  lire, d'où `--bypass-lock`. Sa clé publique est déposée dans
  `backup/.ssh/authorized_keys` par `ansible/backup.yaml`. La clé d'hôte de
  la Storage Box est celle des hôtes (`backup_storage_box_host_key`,
  `ansible/group_vars/all/variables.yml`) ;
- `RESTORE_TEST_BORG_PASSPHRASE` : `backup_passphrase`, commune à tous les
  dépôts ;
- `RESTORE_TEST_PUSH_URL` : le moniteur.

## `apps.json`

Clé : celle du moniteur de sauvegarde (entrée de `local.websites`, ou
`pangolin`) ; `tofu test` de `pangolin_config` échoue si une app sauvegardée
manque ou si une app retirée y reste.

- `host` : hôte de `backup_storage_box_hosts`, dossier `backup/<host>` ;
- `repo` : dossier du dépôt sous celui de l'hôte, et `borgmatic_app_name`
  (dossier de staging SQLite) ;
- `role` : rôle Ansible dont le `compose.yaml` donne l'image de la base ;
- `allow_empty_databases` (facultatif, `true`) : un dump PostgreSQL ou
  MariaDB rejoué sans aucune table ne fait pas échouer l'app. Réservé à une
  base vide par construction (`nginx_demo` : sa démo ne crée aucun schéma),
  jamais pour faire taire une vraie app.

## Lancer à la main

Actions → « Restore test » → Run workflow ; `apps` restreint à une liste
(`betisier,rss`), vide pour tout tester et mettre à jour le moniteur.
