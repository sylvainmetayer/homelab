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

## Check data trimestriel

`.github/workflows/borg-check.yaml` (le 5 de janvier, avril, juillet et
octobre à 02:00 UTC, ou à la main) lance sur chaque dépôt de `apps.json`
`borg check --archives-only --verify-data`, ce que lance
`borgmatic check --only data` : chaque objet du dépôt est téléchargé, son MAC
vérifié et il est déchiffré. Les hôtes font déjà le `repository` (toutes les
2 semaines) et `archives` (tous les mois) de borgmatic, mais jamais `data`.

- **Lecture seule.** Même sous-compte, mêmes secrets, même environnement
  `restore-test` (lisible depuis `main` seulement) que le restore test,
  accès factorisé dans `.github/actions/storage-box-readonly`. Dans borg
  1.4.5 (`archive.py`, `ArchiveChecker`), sans `--repair`, rien n'est écrit
  dans le dépôt : `put`, `delete` et le `commit` final sont tous sous
  `if self.repair`. `--archives-only` saute `Repository.check`, la seule
  partie qui réécrit le fichier `config` du dépôt même sans `--repair` (elle
  y efface `last_segment_checked` ; avec `--bypass-lock`, borg ignore le
  refus d'écriture, « expected when working on read-only repositories »).
  `--repair` n'apparaît nulle part, et le sous-compte refuserait toute
  écriture de toute façon.
- **Un dépôt à la fois** (`max-parallel: 1`, groupe de concurrence partagé
  avec le restore test) : `--verify-data` lit tout le dépôt sur la Storage
  Box.
- **Durée.** `--verify-data` télécharge le dépôt entier (taille dédupliquée et
  compressée) : à 20 à 50 Mo/s entre la Storage Box et un runner, 70 à
  180 Go/h. Les petits dépôts prennent quelques minutes ; immich, nextcloud
  et paperless dominent. Un job a 345 min (sous le plafond de 6 h d'un
  runner hébergé) : environ 400 Go au débit bas. Toute la Storage Box (BX11,
  1 To) passe en 6 à 14 h, avant les sauvegardes de 23:00 UTC. Chaque job
  écrit sa durée et son nombre de blocs : le premier run donne les vraies
  valeurs. Un dépôt qui dépasse échoue sur le timeout de l'étape ; borg 1.x
  ne sait pas reprendre un `--verify-data` (`--max-duration` n'existe qu'avec
  `--repository-only` et écrit dans le dépôt).
- **Sans verrou.** Une sauvegarde qui écrit pendant la vérification (create,
  prune, compact) fait disparaître des blocs ou en laisse d'orphelins : si la
  dernière archive a changé entre le début et la fin, l'échec est déclaré
  « non concluant », à relancer hors de la nuit.
- **Journaux.** Mêmes règles que le restore test : ni les arguments de
  `borg check` ni sa sortie (elle nomme les fichiers touchés), seulement le
  nombre de blocs vérifiés et d'erreurs.
- **Notification.** Pas de moniteur Uptime Kuma : un push ne peut pas
  attendre plus de 24 jours, et pousser sur « Restore test » serait effacé
  par le restore test suivant. Un run planifié en échec envoie la
  notification GitHub d'Actions (à celui qui a écrit la ligne `cron`).

Actions → « Borg data check » → Run workflow ; `apps` restreint à une
liste, vide pour tout vérifier.

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
- `allow_empty_databases` (facultatif, liste de noms de bases) : le dump
  PostgreSQL ou MariaDB d'une base listée peut être rejoué sans aucune table
  sans faire échouer l'app ; les autres bases de l'app restent tenues d'en
  avoir une. Réservé à une base vide par construction (`nginx_demo_db` : la
  démo `nginx_demo` ne crée aucun schéma), jamais pour faire taire une vraie
  app.

## Lancer à la main

Actions → « Restore test » → Run workflow ; `apps` restreint à une liste
(`betisier,rss`), vide pour tout tester et mettre à jour le moniteur.
