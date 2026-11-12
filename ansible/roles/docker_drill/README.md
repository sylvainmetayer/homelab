# Rôle `docker_drill`

La copie jetable de la VM docker sur Hetzner Cloud (`tofu/pangolin/drill.tf`) :
exercice de reconstruction depuis Borg, et hébergeur provisoire le jour d'un
sinistre. Procédure complète, feuille de temps et vérifications :
[`docs/runbooks/reconstruction-vm-docker.md`](../../../docs/runbooks/reconstruction-vm-docker.md).

Il ne tourne que si `drill_mode` est vrai (`group_vars/drill/`, posé sur le
seul groupe `drill` de `hetzner.py`) ; `docker.yml` le garde par `when:` et un
`assert` en tête de play refuse un hôte qui aurait l'un sans l'autre.

## Le mode exercice : un interrupteur, `drill_mode`

Lancer `docker.yml` contre la copie : `-e drill_target=drill` (`hosts:` vaut
`docker` sans cela : la production n'est jamais visée par erreur de frappe du
groupe). `-e docker_drill_key_file=<fichier>` donne la clé du sous-compte
`restore-test`.

| Rôle ou tâche | Sur la copie | Pourquoi |
|---|---|---|
| `pre_tasks` de `docker.yml` | `terraform_outputs = {}` | chaque URL push Uptime Kuma, client OIDC et clé de la passerelle IA que les rôles lisent dans le state tombe sur `default('')` : rien ne rapporte à la production, aucune appli ne s'y authentifie ni n'y dépense de budget |
| `newt` | **exclu** | il se connecterait au site `docker` avec les identifiants de production et volerait son trafic ; le réseau `newt` est créé sans lui (ce rôle) |
| `borgmatic` (hôte) | sans clé générée, **sans service ni minuteur, masqués** | la clé est celle du sous-compte `restore-test` ; une sauvegarde ne peut pas partir |
| `borgmatic` (`app.yml`) | configuration écrite, **jamais de `repo-create`** | la configuration sert `borgmatic extract` et `restore` ; les dépôts sont ceux de production |
| `borg-readonly` (`borgmatic_borg_bin`) | refuse `create`, `prune`, `compact`, `delete`, `recreate`, `rename`, `init`, `key`, `upgrade`, `serve`, `break-lock`, `with-lock`, `import-tar`, `transfer`, `config`, `--repair` | deuxième verrou après le système de fichiers de la Storage Box ; pose `--bypass-lock` (borg 1.x verrouille même pour lire) |
| `beszel`, `beszel_agent` | **exclus** | le hub restauré alerterait sur chaque agent injoignable, vers le ntfy de production |
| `victoria_logs`, `log_agent` | **exclus** | pas de journaux vers la production, pas de comptes vmauth en clair sur la copie |
| `homepage` | **exclu** | ses widgets interrogent Beszel, Uptime Kuma, Pangolin et Proxmox avec leurs comptes |
| `healthlog` | **exclu** | sa synchronisation horaire rafraîchirait les jetons Withings de la base restaurée ; ces jetons tournent à chaque usage, la production perdrait les siens. Sa restauration se prouve par le test de la CI et la restauration d'essai de `healthlog.md` |
| `mem_report`, `update_notify`, `cost_report` | **exclus** | rapports ntfy et carte Homepage, sans objet sur une copie |
| `ci_key_audit`, `log_alerts`, `dav_copy` | **exclus** | alertes et pushs de production ; `dav_copy` (rôle temporaire) pousserait les agendas et contacts vers Infomaniak |
| `00-setup.yaml` (donc `ssh_login_notify`, `canary`) | **`!drill`** | Telegram, jetons pièges : jamais déclenchés par la copie ; l'utilisateur et la clé viennent de cloud-init |
| `security` | joué ; SSH ouvert à toute adresse côté `ufw` | le pare-feu Hetzner filtre ; `security_mta_enabled` reste à `false` : pas de relais de courrier |
| applis (`rss`, `nextcloud`…) | jouées, démarrent à vide, puis `drill-restore-app` | URL push vides, OIDC et clés IA vides : connexion locale, aucune dépense |
| `docs_site` | joué | sans état, rien ne sort |

Hors de ce rôle : le pare-feu Hetzner (`tofu/pangolin/drill.tf`) n'ouvre que SSH
en entrée et ne laisse sortir que DNS, NTP, HTTP(S) et le port 23 de la Storage
Box : ni SMTP, ni IMAP (les applis restaurées envoient par `mail.infomaniak.com`
sur 587/465 avec les identifiants de la vraie, la relève de Papra lit une vraie
boîte), ni SSH vers un hôte de production. Les sorties HTTPS que les applis
ouvrent d'elles-mêmes (récupération de flux RSS, version d'Immich…) restent
possibles : une appli qui poste vers un webhook HTTPS enregistré dans ses
données le ferait ; la liste des applis concernées et ce qui les en empêche est
dans le runbook.

## Outils posés sur la copie

- `/usr/local/sbin/drill-restore-app <appli>` : arrête `dc@<appli>`, extrait la
  dernière archive dans `/var/restore/<appli>` (jamais sur `/` : l'archive porte
  les configurations borgmatic de production), met en place chaque dossier source
  par `mv`, remet les copies SQLite, rejoue les dumps PostgreSQL / MariaDB
  (conteneur de la base seul démarré, base PostgreSQL recréée vide avant le
  dump pour qu'une extension comme PostGIS ne bloque pas le `DROP`, `borgmatic restore`), relance l'appli, et
  écrit une ligne `RESTORE-RESULT` pour la feuille de temps.
- `/usr/local/sbin/drill-check [appli…]` : sonde HTTP sur l'IP du conteneur
  (réseau `newt`, sans suivre de redirection) et tables attendues non vides, d'après
  `.github/restore-test/apps.json` (copié dans `/usr/local/share/drill/`).
  `.github/scripts/test_drill_check.py` garde sa table alignée sur ce fichier
  et sur les `website_*.tf`.
- `/usr/local/bin/borg-readonly`.

## Ajouter une appli à la VM docker

Son rôle fonctionne tel quel sur la copie. Si elle est sauvegardée, elle a une
entrée dans `apps.json` : ajouter alors sa sonde dans `HTTP` de
`files/drill-check.py` (le test de `.github/scripts` échoue sinon). Si elle
envoie quelque chose à l'extérieur de sa propre initiative (courrier, webhook,
push), l'écrire dans la section « Effets sortants » du runbook, et l'exclure de
`docker.yml` (`when: not (drill_mode …)`) si rien d'autre ne l'arrête.
