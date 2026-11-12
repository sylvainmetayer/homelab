# Test de restauration des dépôts borg

`.github/workflows/restore-test.yaml` (le 1er et le 15 du mois à 10:00 UTC,
ou à la main) restaure la dernière archive de chaque dépôt de `apps.json` sur
un runner GitHub, loin des hôtes qui la produisent (issue #444). Pour chaque
dépôt (`.github/scripts/restore_test.py`) :

- la dernière archive doit dater de moins de 28 h (une nuit manquée
  suffit) : une sauvegarde qui ne tourne plus (un dump qui échoue chaque
  nuit, comme celui de Nextcloud en octobre 2026) laisse une vieille archive
  qui, elle, se restaure ;
- l'archive doit contenir un dump ou une copie SQLite de chaque type listé
  dans `databases` (`apps.json`), et d'aucun autre : un type dont plus aucun
  dump ni copie ne s'écrit fait échouer l'app au lieu de passer sur les seuls
  fichiers. Ce contrôle est par type ; chaque base nommée dans
  `expected_tables` doit en plus être présente : une seconde base listée là
  qui disparaît fait échouer l'app ;
- un échantillon de 20 fichiers (≤ 5 Mio) est extrait : borg vérifie chaque
  bloc qu'il déchiffre ;
- les dumps PostgreSQL (`pg_restore`) et MariaDB (`mariadb`) sont rejoués
  dans un conteneur jetable de l'image de la base du rôle (lue dans son
  `compose.yaml`) ;
- les copies SQLite (`/var/lib/borgmatic-sqlite/<dépôt>/`) passent
  `PRAGMA integrity_check` ;
- le contenu de chaque base est lu : les tables de `expected_tables` doivent
  exister et avoir au moins une ligne, et une base sans liste doit avoir au
  moins une table non vide (sauf `allow_empty_databases`, voir plus bas). Un
  dump d'un schéma sans données échoue. Une base que l'app a recréée vide
  garde des lignes dans ses tables de migrations : seules ses
  `expected_tables` peuvent la repérer, si elles ne se remplissent pas seules
  au démarrage.

Les journaux d'un dépôt public sont publics : les commandes qui portent des
chemins de l'archive (`borg list`, `borg extract`) ou des lignes d'un dump
(`pg_restore`, `mariadb`) n'y montrent pas leurs arguments, les requêtes sur le
contenu non plus, et aucune commande n'y montre sa sortie d'erreur (seule exception : la dernière ligne de
`borg list --json`, le message de borg quand le dépôt ne s'ouvre pas). Cette
ligne et les commandes borg affichées passent par `redact()` : URL `ssh://`,
`compte@hôte`, hôte de la Storage Box et chemins (absolus, entre guillemets ou
à plusieurs segments) sont masqués, le message de borg et le nom de
l'exception restent. Ni
journaux des conteneurs de base, ni détail d'`integrity_check`, ni traceback
Python (seulement le type de l'exception). Pour le détail d'un échec, rejouer
la commande depuis un poste.

Les sauvegardes vzdump de Proxmox (VM docker, LXC newt), qui ne passent pas
par Borg, ont leur propre test sur l'hôte même, le 2 et le 16 du mois
(rôle `vzdump_restore_test`, `ansible/pve.yml`) : voir
`docs/runbooks/test-restauration-vm.md`.

Rien d'autre n'est téléchargé : immich ne coûte que la liste de l'archive,
le dump de sa base et l'échantillon.

Le dernier job pousse le résultat global sur le moniteur Uptime Kuma
« Restore test » (`tofu/pangolin_config/restore_test_monitor.tf`, 20 jours :
le provider plafonne un push à 24). Le détail par app est dans le run. Un run
manuel limité à quelques apps ne pousse rien.

## Accès et secrets

Environnement GitHub `restore-test`, lisible depuis `main` seulement
(`tofu/github/environments.tf`), distinct de `production` pour que
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
  dépôts, et rien d'autre : la graine des secrets d'appli (`app_secrets_master`,
  ADR 0034) n'y va pas, `restore_test.py` ne dérive aucun secret ;
- `RESTORE_TEST_PUSH_URL` : le moniteur.

## `apps.json`

Clé : celle du moniteur de sauvegarde (entrée de `local.websites`, ou
`pangolin`, ou `jellyfin` sur le NAS) ; `tofu test` de `pangolin_config` échoue si une app sauvegardée
manque ou si une app retirée y reste. Ce test ne voit que les sauvegardes qui
ont un moniteur : `check_restore_coverage.py` (job Lint) part de ce que les rôles
sauvegardent (`borgmatic_app_name`, une par instance de `flip_planning`) et échoue
sur un dépôt ni dans ce fichier ni dans son `EXCLUDED`, qui porte la raison écrite
de chaque exclusion, sur une entrée qu'aucun rôle ne sauvegarde et sur une
exclusion périmée. Exclus aujourd'hui : `mediamanager` (à l'essai), `ugos_config`
(fichiers texte d'UGOS, rôle `nas`). Une sauvegarde
dont l'interrupteur `<x>_backup_enabled` vaut `false` n'est pas exigée (`kdrive`,
`demo_planning_kc`, `exemple_planning`) ; passée à `true`, elle le redevient.

- `host` : hôte de `backup_storage_box_hosts`, dossier `backup/<host>` ;
- `repo` : dossier du dépôt sous celui de l'hôte, et `borgmatic_app_name`
  (dossier de staging SQLite) ;
- `role` : rôle Ansible dont le `compose.yaml` donne l'image de la base ;
- `databases` (obligatoire, liste parmi `postgresql`, `mysql`, `sqlite`) :
  ce que l'archive doit contenir, ni plus ni moins, d'après la configuration
  borgmatic du rôle (`borgmatic_app_postgresql_databases`,
  `_mysql_databases`, `_sqlite_databases`) ; `[]` pour une app sans base.
  `test_restore_test_databases.py` (job Lint) vérifie l'accord avec les
  tâches du rôle ;
- `expected_tables` (obligatoire si `databases` n'est pas vide) : `{ base :
  [tables] }`, ce qui doit exister et avoir au moins une ligne. La base est le
  nom du dump, ou le nom du fichier SQLite d'origine (`db.sqlite`, celui de
  chaque copie d'un glob). Une table hors du schéma `public` s'écrit
  `schéma.table`. Y mettre ce qu'une instance en service remplit forcément,
  jamais une table qui peut se vider seule. Choisies dans le schéma amont de la
  version épinglée, sans lire les vraies archives : à revoir si une montée de
  version renomme une table, l'app échoue alors avec « table attendue absente ». `test_restore_test_content.py`
  (job Lint) vérifie la forme et l'exige sur chaque app qui a une base ;
- `expected_path` (facultatif, chemin tel que borg l'archive, sans `/` initial :
  `opt/apps/immich/library`) : l'archive doit contenir au moins un fichier
  dessous. Avec `source_directories_must_exist: true` (gabarit borgmatic) une
  source absente fait échouer la sauvegarde ; ce contrôle attrape l'archive qui
  n'a plus les données alors que le dump et `compose.yaml` passent. Posé là où
  le dossier de données porte des fichiers autres que la base SQLite (dont la
  copie vivante est exclue) ;
- `allow_empty_databases` (facultatif, liste de bases, mêmes noms) : une base
  listée peut n'avoir aucune table ou aucune ligne sans faire échouer l'app ;
  ses `expected_tables` éventuelles restent exigées, et les autres bases de
  l'app restent tenues d'avoir du contenu. Réservé à une base que rien n'oblige
  à remplir : file d'attente vidée après traitement (`queue.db` de Karakeep,
  `tasks.sqlite` de Papra), journal (`auxiliary.db` de Beszel) ; jamais pour
  faire taire une vraie app ;
- `paused` (facultatif, booléen) : app en pause
  (`docs/runbooks/app-en-pause.md`), arrêtée exprès et sans sauvegarde. Le run
  complet la saute ; un run manuel qui la nomme restaure sa dernière archive
  sans en exiger l'âge. Le `tofu test` de `pangolin_config` exige `paused`
  exactement sur les apps dont le moniteur de sauvegarde est en pause.

## Lancer à la main

Actions → « Restore test » → Run workflow ; `apps` restreint à une liste
(`betisier,rss`), vide pour tout tester et mettre à jour le moniteur.
