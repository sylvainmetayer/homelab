# Runbooks

Un fichier par incident, toujours le même plan : **Symptôme**,
**Diagnostic**, **Réparation**, **Vérification**, **Prévention**. La carte
d'ensemble est dans [../architecture.md](../architecture.md), le pourquoi des
choix dans [../adr/](../adr/README.md).

| Incident | Fichier |
|---|---|
| Une appli répond 503, ou son moniteur Uptime Kuma est rouge | [appli-en-panne.md](appli-en-panne.md) |
| Pangolin injoignable (toutes les applis tombent ensemble) | [pangolin-injoignable.md](pangolin-injoignable.md) |
| flip injoignable (Flip Planning, Promptoramix) | [flip-injoignable.md](flip-injoignable.md) |
| Plus d'Internet à la maison, un site ne charge plus, moniteur « DNS … » rouge (Blocky) ; bascule du DHCP de la Bbox | [dns-blocky.md](dns-blocky.md) |
| Sauvegarde en échec, restauration d'une appli depuis Borg | [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md) |
| Test de restauration vzdump en échec (VM docker, LXC newt), copie 990 restée sur Proxmox | [test-restauration-vm.md](test-restauration-vm.md) |
| Disque plein, VM docker lente | [disque-plein-vm-lente.md](disque-plein-vm-lente.md) |
| Déploiement CI cassé, PR Renovate qui casse une appli | [deploiement-ci-casse.md](deploiement-ci-casse.md) |
| Perte de la clé age, d'une clé SSH ou d'un poste | [perte-cle-ou-poste.md](perte-cle-ou-poste.md) |
| Reconstruction complète de Pangolin depuis Borg | [reconstruction-pangolin.md](reconstruction-pangolin.md) |
| Reconstruction de flip (Flip Planning, Promptoramix) depuis Borg, sans image Hetzner : **jamais joué** | [reconstruction-flip.md](reconstruction-flip.md) |
| Reconstruction de la VM docker depuis Borg, sur un serveur Hetzner Cloud jetable : exercice chronométré, et hébergeur provisoire d'un sinistre | [reconstruction-vm-docker.md](reconstruction-vm-docker.md) |
| Un hôte a changé de clé d'hôte SSH | [cle-hote-ssh-changee.md](cle-hote-ssh-changee.md) |
| Mettre une appli en pause durablement, la reprendre (procédure, pas un incident) | [app-en-pause.md](app-en-pause.md) |
| Renommer le tableau de bord Pangolin (pangolin. en hall.sylvain.cloud) : ordre des deux PR, coupure attendue, vérifications, retour arrière, suite (procédure, pas un incident) | [renommage-pangolin-hall.md](renommage-pangolin-hall.md) |
| Connexion SSH refusée après durcissement (« no matching key exchange ») | [ssh-refuse-apres-durcissement.md](ssh-refuse-apres-durcissement.md) |
| Proxmox injoignable après durcissement (SSH par clé seulement, pare-feu PVE, SDN supprimé) : console physique, `pve-firewall stop`, retour de la config sshd | [proxmox-injoignable-apres-durcissement.md](proxmox-injoignable-apres-durcissement.md) |
| Changer le mot de passe d'une base Postgres ou MariaDB (procédure, pas un incident) | [mot-de-passe-base.md](mot-de-passe-base.md) |
| Quelqu'un reçoit un 403 vide : CrowdSec (débannir, tester un bannissement, retour arrière) | [crowdsec.md](crowdsec.md) |
| DMARC : lire les rapports, monter d'un cran (none → quarantine → reject), ajouter un service qui envoie en notre nom ; CAA : autoriser une autorité de certification (procédure, pas un incident) | [dmarc.md](dmarc.md) |
| Copie de kDrive vers le NAS : mise en place, premier passage, moniteur « kDrive vers NAS » rouge, retrouver un fichier supprimé ou chiffré dans kDrive | [kdrive-nas.md](kdrive-nas.md) |
| Sauvegarde des bases KeePass du poste (notification « Sauvegarde KeePass en échec », première exécution, restaurer une base, test trimestriel, rétention annuelle) | [sauvegarde-keepass.md](sauvegarde-keepass.md) |
| Clients Nextcloud : qui est encore sur le mot de passe de connexion, créer un mot de passe d'application (procédure, pas un incident) | [nextcloud-mots-de-passe-application.md](nextcloud-mots-de-passe-application.md) |
| Passerelle IA (ia.sylvain.cloud) : tester une clé virtuelle, brancher une appli, remplacer une clé, journal des appels (procédure, pas un incident) | [passerelle-ia.md](passerelle-ia.md) |
| Pocket ID (fournisseur d'identité) : étapes de mise en place, secours si l'IdP tombe ou si tous les passkeys sont perdus, claims lus par Pangolin | [pocket-id.md](pocket-id.md) |
| Commits signés sur `main` : signature SSH du poste, clé de signature GitHub, bascule en squash (procédure, pas un incident) | [commits-signes.md](commits-signes.md) |
| Tester la clé age `secours` hors ligne (chaque trimestre), la remplacer (procédure, pas un incident) | [test-cle-secours.md](test-cle-secours.md) |
| Rotation planifiée des secrets : périodes par nature, procédure par secret, date à mettre à jour, alerte « Rotation des secrets » (procédure, pas un incident) | [rotation-des-secrets.md](rotation-des-secrets.md) |
| Un jeton piège a sonné (alerte ntfy urgente « Jeton piège » : clé AWS factice utilisée, fichier leurre ouvert, compte SSH fictif essayé) | [jeton-piege.md](jeton-piege.md) |
| Mises à jour des hôtes Debian (Proxmox, VM docker, Pi, flip, Pangolin : alerte ntfy du lundi, moniteurs « Mises à jour <hôte> ») et d'UGOS : Docker à la main (tous les conteneurs redémarrent), `full-upgrade`, ordre d'arrêt de Proxmox, `nas.yml` après UGOS (procédure, pas un incident) | [mises-a-jour-hotes.md](mises-a-jour-hotes.md) |
| HealthLog (sante.sylvain.cloud) : appli ou base en panne, Withings ne synchronise plus (webhook, synchronisation horaire, reconnexion), clé de chiffrement dérivée de `backup_passphrase`, restauration depuis Borg | [healthlog.md](healthlog.md) |
| Enclosed (pwpush.sylvain.cloud) : lien qui n'ouvre rien ou note déjà lue, création refusée, `enclosed-share` en échec | [enclosed.md](enclosed.md) |
| MediaManager sur le NAS : appli injoignable (Traefik du NAS, certificat), VPN gluetun tombé ou qui fuit, port redirigé de qBittorrent, liens physiques | [mediamanager-nas.md](mediamanager-nas.md) |
| planning.sylvain.dev (Cloudflare Pages) : déploiement en échec, domaine en attente, jeton du beacon, dérive du plan de `tofu/planning` | [planning-vitrine.md](planning-vitrine.md) |
| Immich Swipe (swipe-photos.sylvain.cloud) : erreur de connexion, mode aléatoire, rotation de la clé d'API, rôle Pangolin `immich-swipe` | [immich-swipe.md](immich-swipe.md) |
| OpenPost (posts.sylvain.cloud) : créer l'app Meta, brancher une page Facebook et un compte Instagram, les rebrancher, publication en échec (procédure, pas un incident) | [openpost-reseaux-sociaux.md](openpost-reseaux-sociaux.md) |
| Homepage : carte en erreur ou absente (agenda `ical-filter`, Supervision `kuma-summary`, cartes d'applis `apps-summary`) | [homepage-cartes.md](homepage-cartes.md) |
| Un disque du NAS meurt, ou le NAS entier : ce qui en dépend (vzdump, Jellyfin, kDrive, MediaManager), RAID 1, remise en route | [disque-nas-mort.md](disque-nas-mort.md) |
| L'hôte Proxmox est mort : réinstaller, restaurer la VM docker et le LXC newt depuis vzdump, ordre, conséquences (Blocky, Newt `proxmox-lxc`) | [hote-proxmox-mort.md](hote-proxmox-mort.md) |
| Santé des disques : alertes S.M.A.R.T. de Beszel, alerte hebdomadaire sur l'usure et les secteurs (`smart_check`), contrôle trimestriel, scrub Btrfs du NAS | [sante-des-disques.md](sante-des-disques.md) |
| Coupure de courant : exercice de démarrage à froid, réglages BIOS à vérifier, retour du secteur | [coupure-de-courant.md](coupure-de-courant.md) |
| Le Raspberry Pi ou son SSD est mort : Immich depuis Borg, Blocky, IP et réservation | [pi-mort.md](pi-mort.md) |
| La Bbox est remplacée : DHCP, DNS, réservations d'adresses, IP publique (`home_ip`), Wi-Fi | [bbox-remplacee.md](bbox-remplacee.md) |
| Intrusion supposée, la première heure : isoler, garder les traces, reconstruire, secrets à tourner, dépôts Borg, clé de CI, prévenir les utilisateurs de Flip Planning | [intrusion-premiere-heure.md](intrusion-premiere-heure.md) |
| Partir plusieurs jours (procédure, pas un incident) : couper l'automerge Renovate et les déploiements, contrôle de santé, ce que le foyer peut faire et ne pas faire, retour | [mode-absence.md](mode-absence.md) |
| Support à distance du poste (POC VNC/RDP par Pangolin) : mise en place, test, démontage complet (procédure, pas un incident) | [support-a-distance.md](support-a-distance.md) |
| Support à distance des PC de la famille (Fedora GNOME de papa, Debian GNOME ou X11, Windows Home), installation entièrement à la main sans Ansible : site et ressource Tofu, identifiants Newt, Newt au démarrage, GNOME Remote Desktop + relais, x11vnc, UltraVNC, consentement, tests, démontage (procédure, pas un incident) | [support-a-distance-famille.md](support-a-distance-famille.md) |
| Support à distance des PC de la famille sans `tofu apply` : site et ressource créés à la main dans Pangolin, puis rattrapage du state (PR, imports, plan vide) au retour (procédure, pas un incident) | [support-a-distance-famille-sans-tofu.md](support-a-distance-famille-sans-tofu.md) |
| Pannes passées, ce qui s'est passé (symptôme, cause, ce qui a manqué, action) | [../incidents/README.md](../incidents/README.md) |
| Perte totale de la maison (NAS, Proxmox, Pi et poste ensemble) : reprise par étages avec critère de passage, où reconstruire, ce qui est perdu sans recours, feuille d'exercice « PC vierge » | [perte-totale-maison.md](perte-totale-maison.md) |

## Avant de commencer

Toutes les commandes `mise run …` et `ansible-playbook …` se lancent depuis
`ansible/`, avec mise actif (il charge `secrets/secrets.sops.yaml` dans
l'environnement : l'inventaire dynamique en a besoin pour lire les states
Tofu).

Se connecter aux hôtes :

```bash
cd ansible
mise run ssh        # VM docker (IP lue dans l'inventaire proxmox.py)
mise run ssh_pi     # Raspberry Pi (réseau local seulement)
mise run ssh_newt   # LXC Newt du site proxmox-lxc (réseau local seulement)
mise run ssh_flip   # flip, par rebond sur Pangolin
ssh sylvain@pangolin.sylvain.cloud   # Pangolin (pas de tâche mise)
ssh sylvain@192.168.1.137            # NAS (réseau local seulement)
ssh root@192.168.1.26                # hôte Proxmox (LAN, ou pve.internal avec le client Pangolin)
```

Vérifier que le sshd de docker, du Pi, de newt-lxc et de Pangolin offre
toujours les algorithmes du rôle security, depuis le LAN : `mise run
ssh-audit` (politique `ansible/molecule/security/files/ssh-audit-policy.txt`,
quelques connexions sans authentification par hôte, que fail2ban ne compte
pas). Un hôte en échec a perdu ou changé son durcissement : relancer son
playbook en `--check --diff --tags security`.

L'inventaire vient de `ansible.cfg` (`inventory = ./inventory`, c'est-à-dire
`proxmox.py`, `hetzner.py` et `hosts` ensemble). Ne pas passer
`-i inventory/hosts` : ce fichier ne contient que les hôtes statiques (Pi,
LXC newt, NAS, hôte Proxmox), `docker.yml`, `flip.yml` ou `pangolin.yaml`
n'y trouveraient aucun hôte.

Un `tofu plan` ou un `tofu output` de `tofu/pangolin_config`, cité dans
plusieurs runbooks, suppose le module initialisé : `mise run provider-fork`
(télécharge le fork du provider Pangolin et le miroir `trozz/pocketid`) **avant**
`mise exec -- tofu -chdir=tofu/pangolin_config init`. Son state est chiffré
comme les autres : l'environnement de mise doit porter la phrase de passe
(`TF_VAR_pangolin_config_state_passphrase`, [conventions/opentofu.md](../conventions/opentofu.md)).

Deux règles qui valent pour tous les runbooks :

- **Sylvain applique lui-même.** `tofu apply` et `ansible-playbook` sans
  `--check` touchent la production : relire le plan ou le `--check --diff`
  avant.
- **Merger sur `main` déploie** dès que la PR touche `ansible/roles/**`, un
  playbook d'hôte, ses `host_vars`, un fichier partagé d'`ansible/` ou
  `docs/**` (`deploy-docker-app.yaml`, détail dans
  [deploiement-ci-casse.md](deploiement-ci-casse.md)).
