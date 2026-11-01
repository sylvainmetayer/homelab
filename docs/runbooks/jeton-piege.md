# Un jeton piège a sonné

Les jetons pièges (rôle `canary`, détail dans
`ansible/roles/canary/README.md`) sont de faux identifiants posés sur
docker, pi, pangolin, flip et newt-lxc. Personne n'a de raison d'y toucher :
une alerte veut dire, jusqu'à preuve du contraire, que quelqu'un fouille un
hôte ou a emporté un de ses fichiers.

## Symptôme

Une notification ntfy urgente (priorité 5, gyrophare) :

- topic **`canary`**, « Jeton piège : homelab <hôte> <fichier> », avec un
  courriel de Canarytokens : une **clé AWS factice** (`~/.aws/credentials`
  ou `/opt/s3-backup/.env` de l'hôte nommé dans le mémo) a servi contre
  l'API AWS, depuis l'IP donnée. La clé a quitté l'hôte : quelqu'un a lu le
  fichier, ou une copie (sauvegarde, dépôt, poste) a fuité ;
- topic **`scripts`**, « Jeton piège sur <hôte> » :
  - « fichier piège /home/sylvain/acces-secours.txt (OPEN) » (ou `DELETE`,
    `MOVED_FROM`) : quelqu'un a ouvert, effacé ou renommé le fichier leurre ;
  - « tentative SSH avec le compte fictif : Invalid user borg-restore from
    <IP> … » : quelqu'un essaie le compte cité dans ce fichier (souvent juste
    après l'alerte précédente, ou depuis un autre hôte : le fichier a été lu
    ailleurs).

## Diagnostic

D'abord : est-ce moi ? Un `cat`/`grep -r` dans `~`, un explorateur qui
prévisualise, un test (`README.md` du rôle, « Tester »), une restauration de
sauvegarde. Si oui, rien à faire. Sinon, considérer l'hôte comme compromis
et noter l'heure de l'alerte.

Sur l'hôte (`docs/runbooks/README.md`, « Se connecter aux hôtes ») :

```bash
journalctl -t canary --since -1d          # toutes les alertes, anti-rafale comprise
journalctl -u ssh --since "<heure - 1 h>" # qui était connecté, depuis où, avec quelle clé
journalctl -t ssh-login-notify --since -1d
journalctl _COMM=sudo --since "<heure - 1 h>"
loginctl list-sessions; ps -ef --forest   # sessions et processus en cours
sudo fail2ban-client status sshd          # l'IP du compte fictif, bannie après plusieurs essais seulement (jamais celle du bastion sur flip)
```

Les mêmes journaux sont dans VictoriaLogs (`logs.sylvain.cloud`) : y
chercher `canary`, puis la fenêtre autour de l'heure sur tous les hôtes.
Alerte AWS : la page de gestion du jeton (lien dans le message, et dans
KeePass) donne l'IP, l'agent utilisateur et l'appel AWS tenté.

## Réparation

Compromission avérée ou probable :

1. Couper l'accès : `sudo ufw deny from <IP>` (fail2ban a pu le faire), ou
   arrêter l'hôte depuis Hetzner / Proxmox s'il sert de rebond.
2. Changer ce qui était lisible sur l'hôte : clés SSH du poste
   (`keys/*.pub`, `00-setup.yaml`), secrets des applis de l'hôte
   (`docs/runbooks/rotation-des-secrets.md`), jeton ntfy `scripts`.
3. Reconstruire l'hôte plutôt que le nettoyer (Pangolin :
   `docs/runbooks/reconstruction-pangolin.md` ; les autres : Tofu puis leur
   playbook, données depuis Borg, `docs/runbooks/sauvegarde-et-restauration.md`).
4. Un jeton Canarytokens qui a sonné est brûlé : le désactiver (page de
   gestion), en créer un neuf, `sops set`, `ansible-playbook 00-setup.yaml
   --tags canary --limit <hôte>`. Le fichier piège lu : l'effacer, le rôle
   le recrée avec un autre mot de passe au passage suivant.

Fausse alerte (un outil, pas un humain) : trouver le processus (sur un hôte
avec auditd, `sudo auditctl -w /home/sylvain/acces-secours.txt -p r -k
canary` puis `sudo ausearch -k canary` à la prochaine alerte ; retirer la
règle avec `auditctl -W …`), puis l'écarter : sauvegarde à qui exclure le
fichier, ou déplacer le piège (`canary_trap_file`).

## Vérification

- `systemctl status canary-watch` : `active (running)` sur l'hôte.
- Un test volontaire sonne : `cat ~/acces-secours.txt`, puis
  `ssh -o BatchMode=yes borg-restore@localhost` depuis l'hôte ; deux
  messages sur le topic `scripts` dans la minute.

## Prévention

- Garder le guetteur en marche : il est relancé sans fin par systemd, mais
  rien ne surveille qu'il tourne ; le test ci-dessus après chaque mise à
  jour majeure de l'hôte.
- Ne jamais ouvrir le fichier piège pour le lire « pour voir », ni le
  sauvegarder : une sauvegarde du dossier personnel le ferait sonner
  chaque nuit.
