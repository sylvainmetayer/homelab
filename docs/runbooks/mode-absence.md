# Mode absence : partir sans que le homelab bouge

Procédure, pas un incident. Avant un départ de plusieurs jours (voyage,
déplacement sans poste), Sylvain **fige ce qui se déploie seul**, vérifie que
tout est sain, et dit au foyer ce qu'il peut faire et ne pas faire. Au retour,
il défige. Aucun mécanisme n'a été ajouté : la page assemble des leviers qui
existent déjà ; ce qui manque est dit à la fin (« Ce que le dépôt ne fait pas »).

Les commandes `gh` ci-dessous qui ne viennent pas d'une page du dépôt sont
marquées « à vérifier ». Pendant l'absence, le seul chemin vers la maison est
Pangolin (le client Pangolin, puis le LXC newt) : aucun accès de secours
WireGuard n'existe ([ADR 0015](../adr/0015-acces-de-secours-wireguard.md),
rejetée). Pangolin tombé, il reste la console Hetzner.

## Ce qui bouge sans personne

Le calendrier du dépôt, pour savoir quoi couper et quoi laisser.

| Quoi | Quand | Source |
|---|---|---|
| vzdump (VM docker, LXC) | chaque soir 21:00 | [test-restauration-vm.md](test-restauration-vm.md) |
| Borgmatic | 01:00 (NAS 02:30) | [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md) |
| Copie kDrive vers le NAS | 04:00 | [kdrive-nas.md](kdrive-nas.md) |
| Avis de mises à jour des hôtes | chaque lundi matin | [mises-a-jour-hotes.md](mises-a-jour-hotes.md) |
| Test de restauration Borg | 1er et 15 du mois | [../conventions/ci.md](../conventions/ci.md) |
| Test de restauration vzdump | 2 et 16 du mois | [test-restauration-vm.md](test-restauration-vm.md) |
| Trivy, quota de la Storage Box, rotation des secrets, tests complets | chaque lundi | [../conventions/ci.md](../conventions/ci.md) |
| Renovate : PR « weekly stateless automerged updates » | lundi, avant 9 h (Paris) | `renovate.json`, [../conventions/ci.md](../conventions/ci.md) |
| Renovate : images maison (`planning-equipes`, `promptoramix`) | dès publication | `renovate.json` |
| Mises à jour de sécurité Debian, redémarrage nocturne si le noyau l'exige | chaque nuit | [mises-a-jour-hotes.md](mises-a-jour-hotes.md) |

Les deux lignes Renovate sont celles qui **déploient en production sans
Sylvain** : une PR fusionnée seule sur `main` lance `deploy-docker-app.yaml`
([deploiement-ci-casse.md](deploiement-ci-casse.md)). Tout le reste de Renovate
attend un merge à la main.

## Avant le départ

### 1. Couper l'automerge et les déploiements

Dans cet ordre, la veille ou l'avant-veille (jamais pendant un déploiement en
cours : `gh run list --workflow deploy-docker-app.yaml --limit 5`, aucun run
actif) :

1. **Ne rien laisser d'ouvert à moitié.** Merger ou fermer les PR de Sylvain ;
   pas de `tofu apply` ni de playbook en attente (un plan non appliqué
   reste une dérive que personne ne verra).
2. **Renovate** — aucun interrupteur unique dans le dépôt. Deux leviers :
   - les PR déjà ouvertes avec fusion automatique : lister
     (`gh pr list --author "app/renovate"`, à vérifier) et retirer la fusion
     automatique de chacune (`gh pr merge --disable-auto <n>`, à vérifier) ; Renovate peut la
     remettre à son prochain passage tant qu'il n'est pas en pause, d'où le
     point suivant puis l'étape 3, qui est le vrai filet ;
   - empêcher les suivantes : mettre l'application Renovate en pause dans les
     réglages GitHub (hors dépôt, à vérifier), ou, par une PR qui ne déploie
     rien (`renovate.json` n'est dans aucun chemin de
     `deploy-docker-app`), `"enabled": false` au niveau racine de
     `renovate.json`. Les règles « Paused apps » utilisent déjà
     `enabled: false` ([app-en-pause.md](app-en-pause.md)) ; le niveau racine
     n'a pas été essayé ici : à vérifier avec une PR de test ;
3. **Déploiements** — désactiver le workflow `deploy-docker-app.yaml`
   (onglet Actions de GitHub, la même coupure que
   [intrusion-premiere-heure.md](intrusion-premiere-heure.md), étape 6 ; en
   ligne de commande `gh workflow disable deploy-docker-app.yaml`, à
   vérifier). Même si une PR fusionne, rien n'atteint les hôtes : cela coupe
   aussi les `schedule` quotidiens du matin (ADR 0029), qui rattrapent sinon
   `main`. Au retour, le
   premier run déploie tout ce qui a changé depuis le dernier run **réussi**
   (`conventions/ci.md`), rien n'est perdu.
4. Ne **pas** merger de PR qui touche `docs/**` : cela déploie aussi (tag
   `docs_site`).

Les tâches planifiées de GitHub (lundi) restent actives : ce sont elles qui
alertent. GitHub désactive un workflow planifié après 60 jours sans activité
du dépôt ([deploiement-ci-casse.md](deploiement-ci-casse.md)) : au-delà d'un
mois d'absence, y penser.

### 2. Contrôle de santé

À faire dans les 48 heures avant le départ, et noter chaque écart :

- **Uptime Kuma** : tous les moniteurs verts, en particulier le groupe
  Backups et les moniteurs « Test restauration vzdump », « Restore test »,
  « Storage Box », « Rotation des secrets », « Clé de CI : contrôle »,
  « DNS Raspberry Pi » et « DNS LXC newt ». Un moniteur rouge qu'on laisse est un moniteur qui ne
  sonne plus.
- **La nuit d'avant** : tous les moniteurs « Backup … » verts le matin
  ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)). Une seule
  nuit manquée suffit à les faire sonner à 26 h ; si l'absence dépasse les 9
  jours des instantanés de la Storage Box, une panne de sauvegarde non vue
  devient irréparable ([intrusion-premiere-heure.md](intrusion-premiere-heure.md),
  étape 5).
- **Disques** : espace de la VM docker et S.M.A.R.T. du NAS dans Beszel
  ([disque-plein-vm-lente.md](disque-plein-vm-lente.md),
  [disque-nas-mort.md](disque-nas-mort.md)).
- **Mises à jour en attente** : l'avis du lundi (ntfy et moniteurs « Mises à
  jour … ») traité ou accepté ; un hôte qui attend un redémarrage ou une montée
  de Docker doit le faire **avant** le départ, pas pendant
  ([mises-a-jour-hotes.md](mises-a-jour-hotes.md)).
- **Dérive** : `tofu plan` dans `tofu/pangolin_config` sans changement
  inattendu ; `ansible-playbook <hôte>.yml --check --diff` sur les hôtes
  touchés récemment.
- **Échéances** : « Rotation des secrets » vert et aucune rotation due dans les
  30 jours qui suivent le retour ([rotation-des-secrets.md](rotation-des-secrets.md)) ;
  `dernier_test` de [test-cle-secours.md](test-cle-secours.md) à moins de 100 jours
  **à la date du retour**, sinon refaire le test avant de partir ;
  Storage Box sous les 80 % ([../conventions/ci.md](../conventions/ci.md)).
- **Les alertes arrivent** : Telegram et ntfy reçoivent un message de test ;
  l'alerte « aucun abonné » de ntfy est muette (le téléphone est abonné,
  [ntfy-topic-retire.md](../incidents/ntfy-topic-retire.md)).
- **L'accès à distance marche** : le client Pangolin du poste emporté ouvre
  l'hôte Proxmox ou une ressource privée ; une clé SSH autorisée est sur le poste
  emporté, et la console Hetzner (Pangolin, flip) est atteignable avec ses
  seconds facteurs ([pangolin-injoignable.md](pangolin-injoignable.md) dit quand
  l'ouvrir ; ce que le dépôt ne dit pas : où sont ces seconds facteurs).
- **Copies à jour** : lancer `restore-test.yaml` à la main s'il date de plus
  d'une semaine (`gh workflow run restore-test.yaml`, à vérifier).

## Pendant l'absence : ce que le foyer peut faire, et ne pas faire

Le foyer ne gère pas le homelab. Il est les yeux et les mains sur place, et
ne dépanne jamais à la place de Sylvain. Ce qui suit est une proposition, à
valider avec lui avant le départ ; ce qu'il peut atteindre (Homepage, client
Pangolin, tableau de bord Uptime Kuma, clés) : à vérifier, le dépôt ne le dit pas.

**Peut faire**

- Regarder les voyants et l'alimentation : Bbox, NAS, hôte Proxmox, Pi. Après
  une coupure de courant, attendre vingt minutes avant de conclure quoi que ce
  soit ; la Bbox et le Pi reviennent seuls en général (à vérifier).
- Redémarrer la **Bbox**, en la débranchant dix secondes
  ([bbox-remplacee.md](bbox-remplacee.md) dit ce que la box doit servir : la
  remettre en route, jamais la réinitialiser).
- Redémarrer le **Pi** (Immich s'arrête quelques minutes, le premier Blocky
  aussi : le second répond, [dns-blocky.md](dns-blocky.md)), mais pas entre
  01:00 et 05:00 (sauvegarde d'Immich, [pi-mort.md](pi-mort.md)).
- Dire à Sylvain **quoi, depuis quand, à quelle heure**, avec une photo des
  voyants : c'est le renseignement qui lui manque.
- Utiliser ce qui marche (Wi-Fi, photos) et dire ce qui ne marche pas.

**Ne pas faire**

- Éteindre, débrancher ou déplacer le **NAS** ou l'**hôte Proxmox**, et ne
  jamais les arrêter entre 21:00 et 05:00 (vzdump, sauvegardes, copie kDrive) :
  une extinction brutale pendant un job abîme une sauvegarde, et le NAS porte
  la VM docker.
- Retirer ou remplacer un disque, appuyer sur un bouton « reset », réinitialiser
  la Bbox, le NAS ou le Pi aux réglages d'usine.
- Toucher aux câbles réseau ou au branchement d'un hôte (les adresses sont
  fixes ou réservées par l'adresse MAC).
- Se connecter aux hôtes, lancer une commande, un playbook ou `tofu`, merger
  ou approuver une PR, lire ou changer un secret, rouvrir le workflow de
  déploiement.
- Supprimer des photos sur les téléphones pour « libérer de la place » : la
  sauvegarde d'Immich n'a lieu qu'une fois par nuit ([pi-mort.md](pi-mort.md)).
- Réparer par tâtonnement : mieux vaut un service tombé quelques jours qu'un
  disque ou une base abîmés.

**Que dire à Sylvain, et par où** (à fixer avant le départ) : le canal, et
qui prévient qui si Sylvain ne répond pas. Les alertes, elles, lui arrivent déjà
sur Telegram et ntfy.

**Si Sylvain reste injoignable plusieurs jours** : patienter, rien d'autre. Les services publics (Pangolin, Flip Planning) sont hors de la
maison et tiennent ; ce qui dépend de la maison attend.

## Au retour

1. Lire ce qui est arrivé : alertes ntfy et Telegram, `gh run list` (rien n'a
   déployé), moniteurs Uptime Kuma, la nuit dernière.
2. Réactiver le workflow (`gh workflow enable deploy-docker-app.yaml`, à
   vérifier) et relire les commits fusionnés pendant l'absence **avant** : le
   premier run (prochain push, `schedule` du matin ou `workflow_dispatch`, la
   réactivation seule ne lance rien) les déploie tous. Si des PR Renovate ont fusionné, regarder
   leurs moniteurs ensuite ([deploiement-ci-casse.md](deploiement-ci-casse.md)).
3. Remettre Renovate (application ou PR inverse de `renovate.json`). Les
   versions parues pendant l'absence arrivent le lundi suivant.
4. Rejouer les contrôles de « Avant le départ, 2 » qui ont une échéance
   (sauvegarde de la nuit, mises à jour en attente, rotations).

## Ce que le dépôt ne fait pas

À décider par Sylvain ; rien n'a été ajouté :

- **Pas d'interrupteur unique** pour Renovate ni pour le déploiement : trois
  gestes à la main (PR ouvertes, application Renovate, workflow). Un
  interrupteur serait un rôle de `renovate.json` ou un fichier lu par
  `deploy-docker-app.yaml`, ce que ce dépôt ne fait pas aujourd'hui.
- **Pas de voyant « tout va bien »** pour le foyer : Uptime Kuma et Beszel sont
  faits pour Sylvain. Un simple message hebdomadaire de santé (digest ntfy, comme
  celui de Renovate le lundi) manque ; à vérifier si Homepage répond à ce besoin.
- **Pas d'accès de secours** si Pangolin tombe pendant l'absence
  (choix assumé, [ADR 0015](../adr/0015-acces-de-secours-wireguard.md) rejetée).
- **Pas de second administrateur** : personne d'autre que Sylvain n'a les clés
  ni la procédure ([matrice des données](../matrice-des-donnees.md), trou 10).
