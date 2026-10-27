# Connexion SSH refusée après durcissement

Le rôle `security` (pangolin, flip, docker, pi, newt-lxc) restreint les
algorithmes de sshd à ceux du guide ssh-audit « Hardened Debian 13 »
(`security_ssh_*` dans `ansible/roles/security/defaults/main.yml`) :

| Famille | Offert |
|---|---|
| Échange de clés | `mlkem768x25519-sha256`, `sntrup761x25519-sha512`, `sntrup761x25519-sha512@openssh.com` (post-quantiques seulement : ni curve25519, ni ECDH, ni DH-GEX) |
| Chiffrement | `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`, `aes256-ctr`, `aes192-ctr`, `aes128-gcm@openssh.com`, `aes128-ctr` |
| MAC | `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256-etm@openssh.com`, `umac-128-etm@openssh.com` (etm seulement) |
| Clé d'hôte | `ssh-ed25519` seule (RSA et ECDSA supprimées de `/etc/ssh`) |
| Clés utilisateur acceptées | ed25519, sk-ed25519, RSA SHA-2 ≥ 3072 bits, et leurs certificats |

Un client trop ancien, ou une bibliothèque sans échange post-quantique, est
refusé **avant** l'authentification. fail2ban (mode `normal`) ne compte pas
ces refus : il ne bannit pas l'IP.

## Symptôme

Côté client, l'un de :

```
Unable to negotiate with 192.168.1.216 port 22: no matching key exchange method found. Their offer: mlkem768x25519-sha256,sntrup761x25519-sha512,...
no matching host key type found. Their offer: ssh-ed25519
no matching MAC found. Their offer: hmac-sha2-512-etm@openssh.com,...
```

PuTTY / WinSCP : `Couldn't agree a key exchange algorithm`. paramiko :
`IncompatiblePeer: Incompatible ssh peer (no acceptable kex algorithm)`.
Dropbear : `No matching algo kex`. Une application mobile affiche souvent
seulement « connexion fermée » ou « algorithm negotiation failed ».

## Diagnostic

1. **Qui est refusé, avec quoi** : sur l'hôte (par une autre session, ou la
   console), le journal de sshd donne l'offre du client :

   ```bash
   sudo journalctl -u ssh --since -1h | grep 'Unable to negotiate'
   # Unable to negotiate with <IP> port <p>: no matching key exchange method found. Their offer: curve25519-sha256,... [preauth]
   ```

   Pas de `mlkem768x25519` ni de `sntrup761x25519` dans « Their offer » :
   c'est le client qui est trop ancien.
2. **Ce que propose un client avant de le brancher sur un hôte** : ssh-audit
   en mode client, sur le poste :

   ```bash
   sudo firewall-cmd --add-port=2222/tcp     # temporaire, perdu au reboot
   mise exec -- ssh-audit -c -p 2222         # attend une connexion
   # depuis le client à tester : ssh -p 2222 <n'importe qui>@192.168.1.164
   ```

   Le rapport liste ses échanges de clés ; il en faut au moins un de la
   table ci-dessus.

### Clients du homelab

Testés le 2026-10-27 contre un sshd Debian 13 configuré comme le rôle, sauf
mention.

| Client | Version | Résultat |
|---|---|---|
| Poste de Sylvain (Fedora 44) : terminal, `mise run ssh*`, VS Code Remote-SSH, sshfs du worker Immich (`compose/immich/README.md`) | OpenSSH 10.2p1 | passe (mlkem), testé |
| Ansible depuis le poste et la CI | OpenSSH système (`[ssh_connection]` d'`ansible.cfg`, pas paramiko) | passe |
| Runner GitHub `ubuntu-26.04` (`deploy-docker-app.yaml`) et son `ProxyJump` par Pangolin vers flip | OpenSSH d'Ubuntu 26.04 (≥ 9.9) | passe ; les deux sauts sont négociés par l'OpenSSH du runner, Pangolin ne fait que relayer le TCP (`-W`) |
| Rebond Pangolin → flip depuis le poste (`hetzner.py`, `mise run ssh_flip`) | OpenSSH 10.2p1 | passe, idem |
| Clé `android` (`keys/android.pub`) | application **inconnue du dépôt** | **à vérifier avant le déploiement** (ssh-audit `-c`, ci-dessus) : Termux (OpenSSH récent) passe ; JuiceSSH (abandonnée) est refusée |
| `ping.yaml` (bannière SSH de `docker-apps.internal`) | `/dev/tcp` de bash, lit la bannière sans négocier | non concerné |
| borgmatic → Storage Box, `backup.yaml`, `restore-test.yaml` | client sortant | non concerné (durcissement serveur seulement ; `ssh_client_hardening: false` laisse `/etc/ssh/ssh_config` tel quel) |
| Beszel (agent ↔ hub) | son propre protocole sur WebSocket | non concerné (pas de sshd) |
| `ssh_login_notify` | `pam_exec` de sshd, après l'authentification | non concerné : un client refusé à la négociation ne notifie rien |
| Proxmox (`tofu/proxmox` en SSH vers `pve`), NAS | hôtes hors rôle `security` | non concernés |

Clés d'hôte : `ansible/known_hosts` et la CI n'épinglent que l'ed25519 de
chaque hôte, qui ne change pas. Le `~/.ssh/known_hosts` du poste a aussi les
clés RSA et ECDSA de docker, newt-lxc, Pangolin et flip (apprises par
`UpdateHostKeys`) : OpenSSH négocie l'ed25519 qu'il connaît déjà, puis retire
de lui-même les clés que l'hôte n'annonce plus.

### Clients tiers

Versions minimales tirées des notes de version, sauf « testé ». Il suffit
d'un des deux échanges post-quantiques ; tous ces clients connaissent ed25519
et les MAC etm dès qu'ils ont sntrup ou mlkem.

| Client | Minimum compatible | Bloqué en dessous |
|---|---|---|
| OpenSSH (Linux, macOS, Termux, VS Code Remote-SSH, sshfs, rsync, scp, sftp) | 8.5 (sntrup) ; 9.9 pour mlkem | Debian 11 (8.4p1, testé : refusé) ; Ubuntu 22.04 (8.9p1), Debian 12 (9.2p1), Ubuntu 24.04 (9.6p1) testés : passent ; macOS ≥ 13 passe |
| OpenSSH de Windows 10/11 (Win32-OpenSSH) | 9.5 (Windows 11 24H2) | 8.1p1 des versions antérieures : refusé, VS Code Remote-SSH compris (il utilise ce client) |
| RHEL / Rocky / Alma 9 | — | OpenSSH 8.7 avec la crypto-policy DEFAULT sans sntrup : refusé sauf politique adaptée |
| PuTTY / plink | 0.78 (sntrup) ; 0.83 pour mlkem | 0.74 testé : refusé ; 0.78 et 0.83 testés : passent |
| WinSCP, FileZilla (moteur PuTTY) | version embarquant PuTTY ≥ 0.78 (WinSCP 6.x, à vérifier) | plus ancien : refusé |
| Dropbear (`dbclient`) | 2025.87 environ (2025.89 testé : passe) | 2022.83 (Debian 12) testé : refusé |
| paramiko (scripts Python, ancien connecteur Ansible `paramiko_ssh`) | aucune version à ce jour | 3.5.1 testé : refusé (ni sntrup ni mlkem) |
| libssh (Remmina, KDE, `ansible-pylibssh`) | 0.11 (sntrup) | 0.10 et avant |
| JSch (Java, IDE JetBrains anciens, Jenkins) | fork `com.github.mwiede` récent, avec Bouncy Castle (à vérifier) | JSch d'origine 0.1.55 : refusé |
| Go `x/crypto/ssh` | version avec `mlkem768x25519-sha256` (2025) | plus ancienne |
| Termius, Blink, ConnectBot, JuiceSSH, clients SFTP mobiles | à vérifier par ssh-audit `-c` | JuiceSSH : refusé |

Consoles de secours : la console Hetzner et la console Proxmox ne passent pas
par SSH, le durcissement ne les touche pas.

## Réparation

**Le client est à jour ailleurs** : le mettre à jour (OpenSSH, PuTTY, appli),
ou passer par le poste. C'est la réparation normale ; un client qu'on ne peut
pas mettre à jour se branche sur le poste, pas l'inverse.

**Il faut un repli pour un client précis** : ajouter l'algorithme à la liste
d'un hôte dans ses `host_vars` (par exemple `security_ssh_kex` avec
`curve25519-sha256` en dernier), puis relancer le playbook en
`--tags security`. Chaque hôte est rejoué par un scénario `security*`, et
tous partagent `ansible/molecule/security/files/ssh-audit-policy.txt`
(correspondance exacte, aussi lue par `mise run ssh-audit` pour tous les
hôtes) et la politique intégrée « Hardened Debian 13 », qui refuse tout
échange non post-quantique : un repli fait échouer le scénario de cet hôte
tant que `tasks/verify_ssh_audit.yml` ne lui donne pas sa propre politique
(et ne lui retire pas l'intégrée). Modifier le fichier commun casserait les
autres scénarios.

**Plus aucun client n'entre** (blocage complet) : passer par la console, puis
revenir en arrière.

| Hôte | Console |
|---|---|
| `pangolin`, `flip` | console Hetzner (Cloud Console → serveur → Console), `sylvain` + son mot de passe |
| `docker` (VM 300) | interface Proxmox → VM 300 → Console, `sylvain` + son mot de passe |
| `newt-lxc` (CT 200) | shell du nœud Proxmox : `pct enter 200` (root, sans mot de passe) |
| `pi` | écran et clavier, ou la carte SD lue sur le poste (`/etc/ssh/sshd_config` sur la partition racine) |

1. Repli immédiat, sur la console : commenter les lignes `KexAlgorithms`,
   `Ciphers`, `MACs`, `HostKeyAlgorithms`, `PubkeyAcceptedAlgorithms`,
   `CASignatureAlgorithms` de `/etc/ssh/sshd_config` (les défauts d'OpenSSH
   reviennent), puis `sudo sshd -t && sudo systemctl restart ssh`. Les
   sessions ouvertes survivent au redémarrage de sshd.
2. Retour en arrière durable : **d'abord** `sudo ssh-keygen -A` sur l'hôte
   (recrée les clés RSA et ECDSA supprimées, nouvelles empreintes), puis
   `git revert` du commit et, depuis le poste,
   `ansible-playbook <playbook> --limit <hôte> --tags security` (PR, puis
   merge : la CI redéploie). devsec remet ses listes par défaut ; sans
   `ssh-keygen -A`, sa tâche de clés d'hôte échoue sur la clé ECDSA absente
   (`file (/etc/ssh/ssh_host_ecdsa_key) is absent, cannot continue` : elle
   règle droits et propriétaire de rsa, ecdsa et ed25519 sans les créer). Ni
   RSA ni ECDSA n'est épinglée dans `ansible/known_hosts`.

## Vérification

```bash
mise run ssh-audit                       # depuis le LAN : docker, pi, newt-lxc, Pangolin
cd ansible && ansible all -m ping --limit 'docker,pi,newt-lxc,pangolin,flip'
mise run ssh_flip                        # le rebond par Pangolin
```

Puis la connexion du client qui avait été refusé.

## Prévention

- Déploiement progressif, une console à portée de main, une session SSH
  ouverte pendant le redémarrage de sshd : d'abord `newt-lxc` (`pct enter`),
  puis `docker`, le Pi, flip, et **Pangolin en dernier** (bastion de flip et
  du runner).
- Avant d'ajouter un client (nouvelle appli, nouveau poste), le passer à
  `ssh-audit -c`.
- Chaque scénario Molecule `security*` vérifie la politique du dépôt et la
  politique intégrée « Hardened Debian 13 » : une montée de devsec ou
  d'OpenSSH qui change ces listes casse la CI avant le déploiement.
