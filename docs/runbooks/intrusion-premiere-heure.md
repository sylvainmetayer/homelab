# Intrusion supposée : la première heure

Prolonge [jeton-piege.md](jeton-piege.md) (les alertes, « est-ce moi ? », les
journaux à lire sur l'hôte, le jeton brûlé) sans le répéter. Ici : quoi
couper, quoi garder, quoi reconstruire, quoi faire tourner, dans quel ordre.
Ce site est sur la VM docker : si elle est touchée, lire cette page sur
GitHub.

## Symptôme

Une alerte sans explication : jeton piège, connexion SSH que Sylvain ne
reconnaît pas (Telegram, rôle `ssh_login_notify`), « Clé de CI utilisée hors
déploiement » ([ci_key_audit](../../ansible/roles/ci_key_audit/README.md)),
processus ou fichier inconnu, sauvegarde qui échoue sans raison.

## Diagnostic

1. Noter l'heure de la **première** trace, pas celle de l'alerte : l'archive
   saine et la fenêtre des snapshots en dépendent.
2. Quel hôte, quel compte ? `sylvain` a `sudo` sans mot de passe
   ([ADR 0028](../adr/0028-cle-ssh-de-ci-root.md)) : **une session `sylvain`
   est une session root**. Un conteneur seul touché, sans sortie du conteneur,
   est un cas plus léger.

## Réparation

### 1. Isoler sans éteindre

Éteindre efface la mémoire et les connexions ouvertes. On coupe le réseau, on
laisse tourner. Se connecter par la **console** (Proxmox, Hetzner, écran),
pas en SSH avec un agent transféré.

| Hôte | Couper |
|---|---|
| VM docker | `qm config 100 \| grep net0`, puis `qm set 100 --net0 <même ligne>,link_down=1` |
| LXC newt | `pct set 200 --net0 <même ligne>,link_down=1` (plus d'accès à la maison ni de CI) |
| Pi, NAS, hôte Proxmox | débrancher le câble réseau (l'hôte Proxmox, c'est aussi la VM et le LXC) |
| Pangolin | pas de coupure, c'est l'entrée de tout : `sudo ufw deny from <IP>`, fail2ban, console Hetzner |
| flip | pas d'IP publique : détacher du réseau privé dans la console Hetzner (à vérifier) |

**VM docker : exporter avant de couper** (étape 2). VictoriaLogs y reçoit les
journaux de tous les hôtes, et la couper les arrête.

### 2. Garder les traces, avant toute reconstruction

- **VictoriaLogs** (`logs.sylvain.cloud`, VM docker) : 30 jours, plafonné à
  5 Gio, **sans sauvegarde**. Exporter la fenêtre utile de chaque hôte (requête
  LogsQL du genre `host:pangolin _time:3d`, syntaxe de la doc VictoriaLogs ;
  export exact : à vérifier). Un intrus root sur la VM peut effacer ou
  falsifier ces lignes.
- **Journal de l'hôte** : `-t canary`, `-u ssh`, `-t ssh-login-notify`,
  `_COMM=sudo` ([jeton-piege.md](jeton-piege.md)). Il est plafonné (rôle
  `host_tuning`) : le copier maintenant. Pangolin : aussi le journal d'accès de
  Traefik, `/opt/pangolin/config/traefik/logs`.
- **État vivant** (commandes Linux usuelles, hors dépôt) : `last -F`,
  `loginctl list-sessions`, `ps -ef --forest`, `ss -tupn`, `docker ps -a`,
  `systemctl list-timers`, les `authorized_keys` de `sylvain` et de root. Copier
  la sortie vers le poste, tirée par le poste, jamais poussée depuis l'hôte.
- **Disque**, VM ou LXC : `vzdump <id> --storage nas-backup --mode snapshot
  --compress zstd --prune-backups keep-all=1`. **Sans ce dernier réglage**, le
  `keep-last=2` du storage élague une archive saine. ~50 Gio pour la VM.
  Hetzner : snapshot du serveur dans la console ; pour Pangolin, convertir une
  image « Backups » en snapshot d'abord
  ([reconstruction-pangolin.md](reconstruction-pangolin.md)). Pi : SSD cloné
  depuis un autre poste, éteint à ce moment-là seulement.

### 3. Reconstruire ou nettoyer

Accès en `sylvain` ou en root : **reconstruire** (règle de jeton-piege.md).
Les données reviennent de Borg, d'une archive **antérieure à la première
trace** (7 quotidiennes, 4 hebdomadaires, 6 mensuelles, 1 annuelle).

| Hôte | Comment |
|---|---|
| Pangolin | [reconstruction-pangolin.md](reconstruction-pangolin.md), depuis Borg et non l'image Hetzner |
| flip | `tofu/pangolin` (serveur), `flip.yml`, bases depuis `backup/flip/*` |
| VM docker | **pas depuis vzdump** (l'archive peut porter l'intrus) : Tofu, `docker.yml`, Borg appli par appli ([hote-proxmox-mort.md](hote-proxmox-mort.md), C) |
| LXC newt | recréé par Tofu, puis `lxc.yml` ; rien à restaurer |
| Pi | [pi-mort.md](pi-mort.md) |
| NAS, hôte Proxmox | à la main ([disque-nas-mort.md](disque-nas-mort.md), [hote-proxmox-mort.md](hote-proxmox-mort.md)) |

### 4. Secrets à faire tourner

Après l'isolement, pas avant (l'intrus relirait les nouveaux). Créer le
nouveau, basculer, vérifier, puis révoquer l'ancien
([rotation-des-secrets.md](rotation-des-secrets.md)). Dans cet ordre :

1. **Les accès** : clés SSH et `host_user_password_hash` si une clé a pu fuir
   ([perte-cle-ou-poste.md](perte-cle-ou-poste.md)) ; la clé de CI (étape 6).
2. **Les jetons de fournisseurs lisibles depuis l'hôte ou par la CI** : ceux du
   fichier Ansible (rapport des coûts Hetzner et OVH, clé OVH du Traefik du
   NAS…). Ceux du fichier racine (Hetzner, OVH, S3 des states, Proxmox)
   seulement si la clé age ou le poste est en cause.
3. **Le tunnel** de l'hôte : ses identifiants Newt (« Identifiants Newt »),
   `pangolin_api_key` si Pangolin a été touché.
4. **Les secrets d'appli de l'hôte** (ce que ses `compose.yaml` et `.env`
   contenaient), clés de session comprises : tout le monde est déconnecté.
5. **Les sauvegardes** : l'hôte reconstruit génère sa clé, `backup.yaml` la
   dépose chez son sous-compte à la place de l'ancienne. `backup_passphrase`
   en dernier, sur incident seulement (`borg key change-passphrase`, dépôt par
   dépôt).
6. Les jetons pièges brûlés ([jeton-piege.md](jeton-piege.md)).

Rien à merger qui déploie tant que la clé de CI est suspecte. Chaque rotation
met à jour `secrets/secrets-rotation.yaml`.

### 5. Les dépôts Borg sont-ils intacts ?

Depuis le poste, par le sous-compte en lecture seule `restore-test` (clé et
paramètres : « Diagnostic » de
[reconstruction-pangolin.md](reconstruction-pangolin.md)), dépôt
`ssh://<user>@<server>:23/./<hôte>/<app>` :

```bash
borg list --bypass-lock --last 10 <dépôt>
borg info --bypass-lock <dépôt>     # une chute de taille = un effacement
```

Attendu : une archive par nuit jusqu'à la veille, 7/4/6/1 au total. Des
archives manquantes, un dépôt vide ou introuvable : un hôte avec sa clé peut
supprimer et élaguer ses propres dépôts. Une archive écrite **après** la
première trace n'est pas fiable.

**La limite de temps est de 9 jours** : la Storage Box garde 9 snapshots
quotidiens (03:00 UTC, après borgmatic), qu'aucun sous-compte ne peut effacer.
Plus ancien, un effacement ne se prouve ni ne se défait. Restauration d'un
snapshot : console Hetzner, Storage Box, Snapshots, compte principal
(procédure exacte : à vérifier). Le test de la CI (1er et 15 du mois) ne
remplace pas ce contrôle.

### 6. La clé de CI (ADR 0028)

Elle donne root (`sudo` sans mot de passe) sur docker, pi, flip, pangolin et
newt-lxc (ni NAS ni hôte Proxmox), et le tunnel OLM ouvre le réseau de la
maison. Avec la clé age `github-actions`, elle lit tout
**`secrets/ansible.sops.yaml`** (secrets d'appli, `backup_passphrase`), pas le
fichier racine. Elle n'est lisible que d'un run sur `main`, mais du code
malveillant dans le job ou un push sur `main` suffit ; `ci_key_audit` ne
signale qu'après coup.

Si elle est suspecte : désactiver le workflow `deploy-docker-app.yaml` (onglet
Actions de GitHub), refaire ses secrets (clé SSH, clé age, identifiants OLM :
« Secrets de la CI à refaire » de
[deploiement-ci-casse.md](deploiement-ci-casse.md) et « Clé age de la CI » de
[perte-cle-ou-poste.md](perte-cle-ou-poste.md)), rejouer `00-setup.yaml` hôte
par hôte (les clés y sont exclusives : l'ancienne part), puis réactiver.

### 7. Prévenir les utilisateurs de Flip Planning

Flip Planning garde les données des personnes planifiées. Prévenir **dès que**
flip, sa base ou `backup/flip/*` a pu être lu, ou Pangolin (il voit le trafic
en clair), ou la clé de CI : sans attendre d'être sûr.

- **D'abord le responsable du traitement** (l'organisateur,
  `flip_planning_legal_responsable_traitement`, dans SOPS, pas dans le dépôt),
  tout de suite. Il décide d'avertir la CNIL (72 h après en avoir eu
  connaissance, RGPD art. 33) et les personnes (art. 34). Sylvain héberge :
  son statut de sous-traitant (art. 33, al. 2) est à vérifier au contrat.
- **Les utilisateurs**, par lui ou avec lui : ce qui est su, ce qui ne l'est
  pas, ce qu'ils doivent faire. Sans délai si le service est coupé ou le
  planning modifié pendant un événement ou une collecte de disponibilités.
- Tourner les secrets de flip déconnecte tout le monde : le dire avant.
  Démo et vitrine (données fictives) : personne à prévenir.

## Vérification

- L'ancien accès ne marche plus (clé refusée, jetons révoqués) ; chaque hôte
  reconstruit a sa ligne dans `ansible/known_hosts`
  ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)).
- Test volontaire des pièges ([jeton-piege.md](jeton-piege.md)), moniteurs
  Uptime Kuma verts dont « Clé de CI : contrôle », sauvegarde de la nuit réussie.
- Rotations datées ; heure de la première trace, copies et décisions notées
  hors du dépôt public.

## Prévention

- Le risque de la clé de CI est accepté (ADR 0028) : cette page limite les
  dégâts, elle ne l'empêche pas.
- Les journaux de tous les hôtes n'ont qu'une copie, sur la VM docker, sans
  sauvegarde : si elle tombe en premier, les preuves tombent avec. Chantier
  non fait, à décider.
