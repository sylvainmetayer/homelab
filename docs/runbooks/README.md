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
| Sauvegarde en échec, restauration d'une appli depuis Borg | [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md) |
| Test de restauration vzdump en échec (VM docker, LXC newt), copie 990/991 restée sur Proxmox | [test-restauration-vm.md](test-restauration-vm.md) |
| Disque plein, VM docker lente | [disque-plein-vm-lente.md](disque-plein-vm-lente.md) |
| Déploiement CI cassé, PR Renovate qui casse une appli | [deploiement-ci-casse.md](deploiement-ci-casse.md) |
| Perte de la clé age, d'une clé SSH ou d'un poste | [perte-cle-ou-poste.md](perte-cle-ou-poste.md) |
| Reconstruction complète de Pangolin depuis Borg | [reconstruction-pangolin.md](reconstruction-pangolin.md) |
| Un hôte a changé de clé d'hôte SSH | [cle-hote-ssh-changee.md](cle-hote-ssh-changee.md) |
| Mettre une appli en pause durablement, la reprendre (procédure, pas un incident) | [app-en-pause.md](app-en-pause.md) |
| Connexion SSH refusée après durcissement (« no matching key exchange ») | [ssh-refuse-apres-durcissement.md](ssh-refuse-apres-durcissement.md) |
| Changer le mot de passe d'une base Postgres ou MariaDB (procédure, pas un incident) | [mot-de-passe-base.md](mot-de-passe-base.md) |
| Quelqu'un reçoit un 403 vide : CrowdSec (débannir, tester un bannissement, retour arrière) | [crowdsec.md](crowdsec.md) |
| DMARC : lire les rapports, monter d'un cran (none → quarantine → reject), ajouter un service qui envoie en notre nom ; CAA : autoriser une autorité de certification (procédure, pas un incident) | [dmarc.md](dmarc.md) |
| Copie de kDrive vers le NAS : mise en place, premier passage, moniteur « kDrive vers NAS » rouge, retrouver un fichier supprimé ou chiffré dans kDrive | [kdrive-nas.md](kdrive-nas.md) |
| Clients Nextcloud : qui est encore sur le mot de passe de connexion, créer un mot de passe d'application (procédure, pas un incident) | [nextcloud-mots-de-passe-application.md](nextcloud-mots-de-passe-application.md) |
| Commits signés sur `main` : signature SSH du poste, clé de signature GitHub, bascule en squash (procédure, pas un incident) | [commits-signes.md](commits-signes.md) |
| Tester la clé age `secours` hors ligne (chaque trimestre), la remplacer (procédure, pas un incident) | [test-cle-secours.md](test-cle-secours.md) |
| Rotation planifiée des secrets : périodes par nature, procédure par secret, date à mettre à jour, alerte « Rotation des secrets » (procédure, pas un incident) | [rotation-des-secrets.md](rotation-des-secrets.md) |
| Mises à jour de l'hôte Proxmox et d'UGOS (alerte ntfy du lundi, moniteurs « Mises à jour Proxmox » / « Mises à jour NAS ») : sauvegarde, `full-upgrade`, ordre d'arrêt, `nas.yml` après UGOS (procédure, pas un incident) | [mises-a-jour-proxmox-ugos.md](mises-a-jour-proxmox-ugos.md) |

## Avant de commencer

Toutes les commandes `mise run …` et `ansible-playbook …` se lancent depuis
`ansible/`, avec mise actif (il charge `secrets.sops.yaml` dans
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
```

Vérifier que le sshd de docker, du Pi, de newt-lxc et de Pangolin offre
toujours les algorithmes du rôle security, depuis le LAN : `mise run
ssh-audit` (politique `ansible/molecule/security/files/ssh-audit-policy.txt`,
quelques connexions sans authentification par hôte, que fail2ban ne compte
pas). Un hôte en échec a perdu ou changé son durcissement : relancer son
playbook en `--check --diff --tags security`.

L'inventaire vient de `ansible.cfg` (`inventory = ./inventory`, c'est-à-dire
`proxmox.py`, `hetzner.py` et `hosts` ensemble). Ne pas passer
`-i inventory/hosts` : ce fichier ne contient que le Pi, `docker.yml` ou
`pangolin.yaml` n'y trouveraient aucun hôte.

Deux règles qui valent pour tous les runbooks :

- **Sylvain applique lui-même.** `tofu apply` et `ansible-playbook` sans
  `--check` touchent la production : relire le plan ou le `--check --diff`
  avant.
- **Merger sur `main` déploie** dès que la PR touche `ansible/roles/**` ou un
  playbook d'hôte (`deploy-docker-app.yaml`).
