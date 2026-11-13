# Support à distance des PC de la famille : installation à la main

Prendre la main sur le PC de papa (Fedora, partie **F** ; ou Debian) ou de mamie (Windows Home) depuis
un navigateur, comme pour le poste de Sylvain
([support-a-distance.md](support-a-distance.md)), mais **sans Ansible ni
checkout du dépôt** : tout ce qui suit se tape sur place, au clavier du PC à
dépanner (procédure, pas un incident).

La chaîne, la même partout :

```
navigateur ──HTTPS + SSO (groupe Pocket ID « support », FR/DE)──▶ Pangolin
   ──tunnel WireGuard──▶ Newt (sur le PC) ──▶ 127.0.0.1:<port> ──▶ serveur VNC
```

Le PC n'ouvre **aucun** port vers Internet ni vers sa box : Newt sort vers
`https://pangolin.sylvain.cloud` et le serveur VNC n'écoute (ou n'est joignable)
que sur la boucle locale. Le client VNC du navigateur parle l'authentification
VNC classique (mot de passe, 8 caractères au plus) : chaque serveur ci-dessous
est réglé pour la lui offrir.

| PC | Bureau | Serveur VNC | Port visé par Newt |
|---|---|---|---|
| Debian, GNOME (Wayland) | GNOME | GNOME Remote Desktop + relais `grd-vnc-relay` | 5901 (relais) |
| Fedora Workstation (PC de papa, partie **F**) | GNOME (Wayland) | GNOME Remote Desktop + relais `grd-vnc-relay` | 5901 (relais) |
| Debian, bureau X11 (Xfce, MATE, Cinnamon, LXQt) | session X11 | x11vnc | 5900 |
| Windows 10/11 Home | Windows | UltraVNC Server (service) | 5900 |

Le RDP ne sert pas ici : Windows Home n'a pas de serveur RDP, et GNOME refuse
le client RDP du navigateur (section « Limites » de
[support-a-distance.md](support-a-distance.md)). Le presse-papiers ne passe
pas par le client VNC du navigateur.

Versions vérifiées le 08/11/2026 : Newt **1.20.0**, Pangolin 1.25.3 (l'image est depuis en `ee-1.26.0`, à revérifier), relais
du commit `ed9d923d`. Ce qui n'a été essayé que sur le poste de Sylvain
(Fedora) est marqué **non testé** : à vérifier à la première installation, et
à corriger ici.

## 0. Avant de partir (chez soi, avec le dépôt)

### 0.1 Créer le site et la ressource du PC (Tofu)

Pas moyen de faire un `tofu apply` (sur place, sans le dépôt) : créer site et
ressource à la main avec [support-a-distance-famille-sans-tofu.md](support-a-distance-famille-sans-tofu.md),
qui remplace 0.1 et 0.2 et dit comment rattraper le state au retour.

Une PR sur `tofu/pangolin_config/remote_support.tf`, sur le modèle de
`pc_sylvain` (à faire faire par Claude : il faut aussi les surcharges des
tests, `tests/invariants.tftest.hcl`) :

```hcl
resource "pangolin_site" "pc_papa" {
  name                  = "pc-papa"
  docker_socket_enabled = true
}

output "pc_papa_newt_id" {
  description = "PC PAPA - Newt ID du site pc-papa"
  value       = pangolin_site.pc_papa.newt_id
  sensitive   = true
}

output "pc_papa_newt_secret" {
  description = "PC PAPA - Newt secret du site pc-papa"
  value       = pangolin_site.pc_papa.newt_secret
  sensitive   = true
}
```

Et l'entrée de `local.remote_desktops` :

```hcl
    pc_papa_vnc = {
      name      = "PC Papa (VNC)"
      mode      = "vnc"
      subdomain = "d-xxxxxx"   # neutre et aléatoire, voir ci-dessous
      site_id   = pangolin_site.pc_papa.id
      port      = 5901         # 5901 si GNOME (relais), 5900 sinon (x11vnc, UltraVNC)
    }
```

- Sous-domaine : `tr -dc a-z0-9 </dev/urandom | head -c6`, préfixé `d-`. Les
  journaux Certificate Transparency sont publics : le nom ne dit pas qu'il y a
  un bureau derrière.
- Le port dépend du bureau : le demander avant (« quand tu te connectes, tu
  as le bureau GNOME ou autre chose ? »), ou le corriger après coup par une
  PR d'un chiffre (modification en place de la cible, sans rien recréer).
- Le site n'est pas dans l'alerte « Site hors ligne » (`local.alert_infra_sites`,
  `alerts.tf`) : un PC éteint ne réveille personne. La notification « PC de la
  famille en ligne » prévue au plan n'existe pas encore.
- Accès : rôle `support`, déjà lié par la boucle `pangolin_resource_role`.
  Qui est dans le groupe Pocket ID `support` prend la main sur **tous** les
  PC : n'y mettre que Sylvain.

Merge, puis plan et apply depuis `main` (skill `pangolin-config-plan`) : il
crée 1 site, 1 ressource, 1 cible, 3 règles de pays, 1 liaison de rôle.

### 0.2 Récupérer les identifiants Newt

Dans un checkout à jour de `main` :

```bash
mise exec -- tofu -chdir=tofu/pangolin_config output -raw pc_papa_newt_id; echo
mise exec -- tofu -chdir=tofu/pangolin_config output -raw pc_papa_newt_secret; echo
```

Les mettre dans une entrée KeePass « Newt pc-papa » (identifiant = ID,
mot de passe = secret), avec l'endpoint `https://pangolin.sylvain.cloud`.
Le secret ne se relit nulle part ailleurs : l'interface de Pangolin ne le
montre qu'à la création, et en régénérer un là-bas désaccorde le state Tofu.

### 0.3 Préparer le mot de passe VNC

Une entrée KeePass « VNC pc-papa » : **8 caractères exactement** (VNC n'en
lit pas plus ; au-delà ils sont ignorés), lettres et chiffres, rien d'autre
(certains serveurs tronquent ou refusent les caractères spéciaux).

### 0.4 À emporter

- KeePass sur le téléphone (identifiants Newt, mot de passe VNC).
- Une clé USB avec, si le réseau sur place est lent ou bridé :
  `newt_linux_amd64` ou `newt_windows_amd64.exe` (release 1.20.0),
  `grd-vnc-relay.py`, l'installeur UltraVNC.

Empreintes SHA-256 de la release Newt 1.20.0 (lues sur GitHub le 08/11) :

| Fichier | SHA-256 |
|---|---|
| `newt_linux_amd64` | `f380273f7f92917d743ab1b0b92da3ca9e8ac72d0a9909c253633de29b4a70cb` |
| `newt_linux_arm64` | `499bfc4eb16c6021e702800118ec89645264b521ae42cf843ba87ed0ecd5a427` |
| `newt_windows_amd64.exe` | `53f01b2635cbaf73a9a6387df4e24724e008fe5f1171af0dc4265f6a1f1100a3` |

Relais `grd-vnc-relay.py` au commit `ed9d923d` :
`7e6dd112334c67525392a780a6672e6edfaaaf87c4195af3cac137d2acce1867`.

## 1. Debian : Newt au démarrage (commun à tous les bureaux)

Dans un terminal, en compte administrateur (`sudo`). Vérifier d'abord le
bureau et l'architecture :

```bash
echo "$XDG_CURRENT_DESKTOP / $XDG_SESSION_TYPE"   # ex. « GNOME / wayland » ou « XFCE / x11 »
dpkg --print-architecture                          # amd64 (ou arm64)
cat /etc/debian_version
```

### 1.1 Binaire

```bash
cd /tmp
curl -fLo newt https://github.com/fosrl/newt/releases/download/1.20.0/newt_linux_amd64
sha256sum newt   # doit afficher f380273f…a70cb (tableau 0.4), sinon NE PAS continuer
sudo install -m 0755 -o root -g root newt /usr/local/bin/newt
/usr/local/bin/newt --version
```

### 1.2 Identifiants (fichier lisible par root seul)

```bash
sudo install -d -m 0755 /etc/newt
sudo install -m 0600 /dev/null /etc/newt/env
sudo nano /etc/newt/env
```

Contenu (valeurs de KeePass, sans guillemets ni espaces) :

```
PANGOLIN_ENDPOINT=https://pangolin.sylvain.cloud
NEWT_ID=<ID de KeePass>
NEWT_SECRET=<secret de KeePass>
```

### 1.3 Service systemd

`sudo nano /etc/systemd/system/newt.service`, contenu identique au rôle
`newt_service` (compte éphémère sans privilège) :

```ini
[Unit]
Description=Newt, Pangolin tunnel client
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/env
ExecStart=/usr/local/bin/newt
Restart=always
RestartSec=10
DynamicUser=yes
StateDirectory=newt
Environment=HOME=/var/lib/newt
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now newt
journalctl -u newt -n 20 --no-pager
```

Attendu dans le journal : `Tunnel connection to server established
successfully!` puis `Client connectivity setup. Ready to accept connections`.
Le site `pc-papa` passe en ligne dans Pangolin (Sites). L'avertissement
`Did not start on site auth daemon: auth-daemon must be run as root` est
normal (fonction SSH de Newt, inutilisée).

En cas d'échec : `invalid credentials` → ID ou secret mal recopié (refaire
1.2, puis `sudo systemctl restart newt`) ; pas de connexion du tout → le
réseau bloque la sortie (tester `curl -I https://pangolin.sylvain.cloud`).

### 1.4 Mise à jour automatique de Newt (PC de la famille)

Décision du 13/11/2026 : ces PC sont difficiles à atteindre, Newt (>= 1.20.0)
se met à jour seul. Le réglage `newt_auto_update` de l'organisation est déjà à
`true` (`tofu/pangolin_config/org.tf`). Il faut aussi que le service puisse
écrire le binaire : sous `ProtectSystem=strict`, `/usr/local/bin/newt` est en
lecture seule (journal : `cannot write to … you may need to run as root`).
Le binaire vit donc dans l'état du service (`/var/lib/newt/newt`) et
`/usr/local/bin/newt` n'est que la graine, recopiée si elle est plus récente.
Compte éphémère, `NoNewPrivileges`, `ProtectSystem=strict` : inchangés.

**Ce que Newt vérifie** (lu dans le code de la 1.20.0) : toutes les 6 h (la
première fois 2 min après le démarrage) il demande à Pangolin, avec son ID et
son secret, s'il existe une version plus récente ; la réponse contient l'URL
de téléchargement et une somme SHA-256 **venues du même serveur** (l'URL n'est
ni limitée à un hôte ni obligée d'être en HTTPS, la somme est facultative). Il
vérifie la somme si elle est fournie, aucune signature. Le contrôle protège
d'un fichier corrompu, pas d'un serveur Pangolin ou d'un compte fossorial
compromis : c'est la confiance acceptée. Puis il écrit un fichier temporaire à
côté du binaire, le renomme sur lui-même et se relance (`exec`, même PID : pas
de redémarrage systemd, le tunnel se rétablit seul).

Le même réglage vaut pour toute l'organisation : les autres Newt (le LXC, le
PC de Sylvain, flip) ne le peuvent pas, leur unité garde le binaire en lecture
seule (rôle `newt_service`, `newt_service_self_update: false`).

#### Mettre à jour un PC déjà installé (1.1 à 1.3 faits)

```bash
sudo install -d -m 0755 /etc/systemd/system/newt.service.d
sudo tee /etc/systemd/system/newt.service.d/auto-update.conf >/dev/null <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'if [ ! -x /var/lib/newt/newt ] || [ /usr/local/bin/newt -nt /var/lib/newt/newt ]; then install -m 0755 /usr/local/bin/newt /var/lib/newt/newt; fi'
ExecStart=
ExecStart=/var/lib/newt/newt
EOF
sudo systemctl daemon-reload
sudo systemctl restart newt
```

(Pour un PC neuf : faire 1.1 à 1.3, puis ces commandes.) Le `ExecStart=` vide
efface celui de l'unité. Contrôler :

```bash
systemctl cat newt | grep -E 'ExecStart'
sudo ls -l /var/lib/private/newt/newt
journalctl -u newt --since "-10min" --no-pager | grep -i -E 'update|cannot write'
```

Pas de `cannot write` dans le journal. Après la première vérification (2 min)
ou la sortie d'une version, `Pangolin → Sites → pc-papa` affiche la version de
Newt et elle monte seule. Une version déjà à jour ne produit aucune ligne.

Mise à jour manuelle plus tard (si l'automatique est en panne) : refaire 1.1
avec la nouvelle version (empreinte de la release), puis `sudo systemctl
restart newt` : la graine, plus récente que la copie de l'état, la remplace
(elle peut rétrograder une copie déjà auto-mise à jour ; Newt remonte seul).

## 2a. Debian GNOME : GNOME Remote Desktop + relais

GNOME partage la session ouverte. Il ne parle VNC qu'en TLS anonyme (type de
sécurité 18), que le navigateur ne négocie pas : le relais ouvre ce TLS à sa
place et ne propose au navigateur que l'authentification VNC classique.
Tout se fait **dans la session de papa, sans sudo**, sauf le pare-feu.

### 2a.1 Paquet

```bash
sudo apt install gnome-remote-desktop python3
grdctl --help | head -3     # la commande doit exister
```

### 2a.2 VNC de GNOME

```bash
grdctl vnc set-auth-method password     # ou « prompt » : voir 2a.5 (consentement)
grdctl vnc set-port 5900
grdctl vnc disable-port-negotiation     # sinon grd prend un autre port si 5900 est pris
grdctl vnc disable-view-only            # sinon on voit sans pouvoir cliquer
grdctl vnc set-password                 # tape le mot de passe de KeePass (8 caractères)
grdctl vnc enable
systemctl --user enable gnome-remote-desktop
systemctl --user restart gnome-remote-desktop
grdctl status
```

Attendu dans `grdctl status`, section `VNC:` : `Status: enabled`,
`Port: 5900`, `Auth method: password`, `View-only: no`,
`Negotiate port: no`. Pour vérifier que le mot de passe est posé sans
l'afficher : `grdctl status --show-credentials | grep -A6 '^VNC' | grep -c Password`.

Non testé sur Debian : l'interface Réglages → Système → Bureau à distance
peut aussi activer le partage ; si elle désactive VNC en touchant au RDP,
relancer `grdctl vnc enable`.

### 2a.3 Relais

```bash
mkdir -p ~/.local/bin ~/.config/systemd/user
curl -fLo ~/.local/bin/grd-vnc-relay \
  https://raw.githubusercontent.com/sylvainmetayer/homelab/ed9d923dc53b0991ba1b2b5627eb0d8426b906fb/ansible/files/grd-vnc-relay.py
sha256sum ~/.local/bin/grd-vnc-relay   # 7e6dd112…e1867 (tableau 0.4), sinon NE PAS continuer
chmod 0700 ~/.local/bin/grd-vnc-relay
nano ~/.config/systemd/user/grd-vnc-relay.service
```

Contenu :

```ini
[Unit]
Description=Relais VNC local devant GNOME Remote Desktop
After=gnome-remote-desktop.service

[Service]
ExecStart=/usr/bin/python3 -I %h/.local/bin/grd-vnc-relay 5901 5900
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
chmod 0600 ~/.config/systemd/user/grd-vnc-relay.service
systemctl --user daemon-reload
systemctl --user enable --now grd-vnc-relay
journalctl --user -u grd-vnc-relay -n 5 --no-pager   # « relais 127.0.0.1:5901 -> grd 127.0.0.1:5900 »
```

Contrôle local de la chaîne, sans mot de passe (doit afficher `[2]`, le type
« mot de passe VNC » offert au navigateur) :

```bash
python3 -I -c "
import socket; c=socket.create_connection(('127.0.0.1',5901),timeout=5)
c.recv(12); c.sendall(b'RFB 003.008\n'); n=c.recv(1)[0]; print(list(c.recv(n)))"
```

Si le relais écrit `grd n'offre pas le type 18 : [2]` dans son journal, cette
version de GNOME parle déjà VNC classique : arrêter le relais
(`systemctl --user disable --now grd-vnc-relay`) et faire viser 5900 à la cible
Pangolin (PR d'un chiffre).

### 2a.4 Pare-feu (grd écoute sur toutes les interfaces)

grd n'écoute pas que sur la boucle locale : sans pare-feu, le 5900 est
joignable depuis le Wi-Fi de la maison (mot de passe de 8 caractères seulement).
Debian n'a pas de pare-feu actif par défaut :

```bash
sudo apt install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable            # la boucle locale reste ouverte, Newt sort librement
sudo ufw status verbose
```

Si papa utilise un partage ou une imprimante qui doit être joint depuis le
réseau (rare sur un PC de bureau), l'autoriser par `sudo ufw allow <port>`.
Variante sans ufw : `firewalld` comme sur Fedora (REJECT de 5900 dans la zone
active).

### 2a.5 Consentement (au choix pour cette machine)

- `grdctl vnc set-auth-method password` : on entre avec le mot de passe, sans
  rien demander à papa.
- `grdctl vnc set-auth-method prompt` : une fenêtre demande à papa d'accepter
  chaque connexion, et le mot de passe n'est plus demandé. Non testé avec le
  relais.

### 2a.6 Limites

- Le partage n'existe que **session ouverte** (service utilisateur) : à
  l'écran de connexion de GDM, personne n'écoute. Pour un PC qui doit être
  joignable sans papa, activer la connexion automatique (Réglages →
  Utilisateurs) ; non testé : le comportement écran verrouillé.
- `SetDesktopSize` ignoré dans le journal de grd : normal, le navigateur
  demande un redimensionnement que GNOME refuse en mode miroir.

## 2b. Debian avec un bureau X11 : x11vnc

Pour Xfce, MATE, Cinnamon, LXQt… en session X11 (`$XDG_SESSION_TYPE` = `x11`).
x11vnc parle VNC classique directement : pas de relais, et `-localhost` le
limite à la boucle locale (pas de pare-feu nécessaire pour lui).

```bash
sudo apt install x11vnc
x11vnc -storepasswd     # tape le mot de passe de KeePass ; écrit ~/.vnc/passwd
chmod 0600 ~/.vnc/passwd
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/x11vnc.service
```

Contenu (non testé, à valider à la première installation) :

```ini
[Unit]
Description=x11vnc, partage de la session X11 (support à distance)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/x11vnc -display :0 -localhost -rfbport 5900 -rfbauth %h/.vnc/passwd -forever -shared -noxdamage
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now x11vnc
journalctl --user -u x11vnc -n 20 --no-pager    # « PORT=5900 »
ss -ltn | grep 5900                              # doit montrer 127.0.0.1:5900, pas 0.0.0.0
```

Si le service ne démarre pas avec la session (certains bureaux n'activent pas
`graphical-session.target`), le lancer par le démarrage automatique du bureau :
Paramètres → Session et démarrage → Démarrage automatique → commande
`x11vnc -display :0 -localhost -rfbport 5900 -rfbauth ~/.vnc/passwd -forever -shared -noxdamage`.

Consentement : ajouter `-accept popup:0` à la commande, une fenêtre demande
alors d'accepter chaque connexion.

## 3. Windows Home : Newt en service et UltraVNC

Tout se fait dans un **PowerShell lancé en administrateur** (clic droit sur
Démarrer → Terminal (administrateur)). Non testé : la procédure suit la doc
de Newt et d'UltraVNC, à valider à la première installation chez mamie.

### 3.1 Newt

```powershell
New-Item -ItemType Directory -Force "C:\Program Files\newt" | Out-Null
Invoke-WebRequest https://github.com/fosrl/newt/releases/download/1.20.0/newt_windows_amd64.exe `
  -OutFile "C:\Program Files\newt\newt.exe"
(Get-FileHash "C:\Program Files\newt\newt.exe" -Algorithm SHA256).Hash
# doit afficher 53F01B26…100A3 (tableau 0.4, en majuscules), sinon NE PAS continuer
cd "C:\Program Files\newt"
```

Premier lancement, pour écrire la configuration du service
(`%PROGRAMDATA%\newt\newt-client\config.json`) :

```powershell
.\newt.exe --id <ID de KeePass> --secret <secret de KeePass> --endpoint https://pangolin.sylvain.cloud
```

Attendre `Tunnel connection to server established successfully!`, puis
`Ctrl+C`. Ensuite :

```powershell
.\newt.exe install
.\newt.exe start
.\newt.exe status
Get-Service | Where-Object { $_.Name -like "*newt*" } | Format-Table Name, Status, StartType
```

Si `StartType` n'est pas `Automatic` :
`Set-Service -Name <nom affiché> -StartupType Automatic`. Journaux :
`%PROGRAMDATA%\newt\logs\newt.log`, ou
`Get-EventLog -LogName Application -Source "newtWireguardService" -Newest 10`.

Le secret passe ici en argument, visible un instant par les autres comptes du
PC : acceptable sur le PC d'une seule personne. SmartScreen peut avertir sur
un `.exe` non signé : « Informations complémentaires » → « Exécuter quand
même », après avoir vérifié l'empreinte.

### 3.2 UltraVNC Server

1. Télécharger l'installeur sur le site officiel <https://uvnc.com> (page
   Downloads, dernière version stable, 64 bits). Rien d'autre que ce site.
2. Installer : cocher **UltraVNC Server** seulement (pas le Viewer, pas le
   « Repeater ») ; aux options, cocher **Register UltraVNC Server as a system
   service** et **Start or restart UltraVNC service**. Le mode service garde
   la main sur l'écran de connexion et sur les fenêtres d'administration
   (UAC).
3. Ouvrir « UltraVNC Server Settings » (menu Démarrer, en administrateur) :
   - **Authentication** : *VNC Password* = le mot de passe de KeePass
     (8 caractères) ; *View-Only Password* vide ; **décocher** *Require MS
     Logon* (le navigateur ne parle que le mot de passe VNC).
   - **Encryption** : aucun plugin (DSM) : le navigateur n'en parle aucun.
   - **Network** : *Accept Socket Connections* coché, port **5900** fixe ;
     **cocher** *Allow Loopback Connections* et *LoopbackOnly* (Newt se
     connecte depuis la machine elle-même, et personne d'autre) ; **décocher**
     *Enable JavaViewer (Web Svr)* (port 5800).
   - **Query on incoming connection** : voir 3.3.
   - Appliquer, puis redémarrer le service :
     `Restart-Service uvnc_service` (PowerShell administrateur).
4. Vérifier :
   ```powershell
   Get-NetTCPConnection -LocalPort 5900 -State Listen | Format-Table LocalAddress, LocalPort
   ```
   L'adresse doit être `127.0.0.1` (ou UltraVNC refuse lui-même tout ce qui
   n'est pas local avec *LoopbackOnly*).

Les mêmes réglages se lisent dans `ultravnc.ini` (dossier d'installation,
`C:\Program Files\uvnc bvba\UltraVNC\`) : `AllowLoopback=1`,
`LoopbackOnly=1`, `MSLogonRequired=0`, `EnableHTTPConnect=0`,
`PortNumber=5900`, `AutoPortSelect=0`. Le mot de passe y est chiffré
(`passwd=`) : le poser par l'interface, pas à la main.

### 3.3 Consentement (au choix pour cette machine)

Dans « UltraVNC Server Settings », *Query on incoming connection* : une
fenêtre demande à mamie d'accepter. Dans `ultravnc.ini` :
`QuerySetting=4`, `QueryTimeout=30`, `QueryAccept=0` (refus si personne ne
répond), et `QueryIfNoLogon=0` pour pouvoir entrer quand la session est
fermée (sinon personne ne peut accepter). Sans fenêtre : laisser
*Query* décoché.

## F. Fedora Workstation (PC de papa) : Newt et GNOME Remote Desktop

> **Rien de cette partie n'a tourné sur un vrai PC Fedora.** Écrite le
> 13/11/2026 d'après les fichiers du dépôt, la politique SELinux de Fedora 44
> (contextes lus avec `matchpathcon` sur le poste de Sylvain, où SELinux est
> **désactivé** : aucun refus n'a donc pu être observé) et le POC du 08/11.
> Chaque point **non testé** est marqué comme tel ; à corriger ici à la
> première installation.

Le site Pangolin `pc-papa` et la ressource `PC Papa (VNC)` sont déjà décrits
dans `tofu/pangolin_config/remote_support.tf` (VNC de la session par le relais,
cible 127.0.0.1:5901, accès au rôle `support` seul, donc à Sylvain seul) : la
section 0.1 n'est pas à refaire, sauf si le bureau de papa n'est pas GNOME
(voir F.1).

### F.0 Le jour J, en bref

**Avant de partir** (chez soi, avec le dépôt) :

1. Merger la PR, puis plan et apply de `tofu/pangolin_config` depuis `main`
   (Sylvain, skill `pangolin-config-plan`) : attendu 1 site, 1 ressource, 1 cible,
   3 règles de pays, 1 liaison de rôle, rien d'autre.
2. Lire l'ID et le secret Newt (section 0.2, sorties `pc_papa_newt_id` et
   `pc_papa_newt_secret`), les mettre dans KeePass « Newt pc-papa » ; mot de
   passe VNC de 8 caractères dans « VNC pc-papa » (0.3). KeePass sur le téléphone.
3. Vérifier que Sylvain est dans le groupe Pocket ID `support`.

**Sur le PC** (terminal, compte avec `sudo`) : F.1 contrôles, F.2 binaire et
somme, F.3 identifiants, F.4 service, F.5 SELinux, F.6 GNOME Remote Desktop et
relais, F.7 pare-feu.

**Depuis chez soi** (F.8) : site `pc-papa` en ligne dans Pangolin → Sites,
version de Newt affichée, puis la connexion de support
(`https://<sous-domaine>.sylvain.cloud`, SSO, mot de passe VNC) depuis le
téléphone en 4G.

### F.1 Contrôles avant de commencer

```bash
cat /etc/fedora-release
echo "$XDG_CURRENT_DESKTOP / $XDG_SESSION_TYPE"   # attendu « GNOME / wayland »
getenforce                                          # « Enforcing » par défaut
uname -m                                            # x86_64 (sinon aarch64, voir F.2)
sudo -v                                             # papa a-t-il sudo ? sinon voir les questions ouvertes
systemctl is-active firewalld
```

- **Wayland seulement.** La session GNOME de Fedora est Wayland (la session X11
  de GNOME a été retirée de Fedora à partir de la 43) : la section 2b
  (x11vnc) ne s'applique pas à Fedora Workstation. Si papa a un autre bureau
  (KDE, Xfce…), cette partie ne vaut que pour Newt (F.2 à F.5, F.7) ; le serveur
  VNC se choisit comme en 2b ou par KDE (non traité ici), et le port de la cible
  est à corriger par une PR d'un chiffre.
- Pas de `dnf` pour Newt : il n'est pas paqueté, c'est le binaire de la
  release GitHub, comme sur Debian.

### F.2 Binaire, avec contrôle de la somme

La version et les sommes sont celles du rôle `newt_service`
(`defaults/main.yml`, version **1.20.0**) et du tableau de 0.4 ; la somme
se **vérifie** avant l'installation (`&&` : rien n'est installé si elle diffère).

```bash
cd /tmp
curl -fLo newt https://github.com/fosrl/newt/releases/download/1.20.0/newt_linux_amd64
echo "f380273f7f92917d743ab1b0b92da3ca9e8ac72d0a9909c253633de29b4a70cb  newt" | sha256sum -c - \
  && sudo install -m 0755 -o root -g root newt /usr/local/bin/newt
/usr/local/bin/newt --version
```

Il doit afficher `newt: OK`, sinon **ne pas continuer**. Sur `aarch64`,
fichier `newt_linux_arm64` et somme `499bfc4e…5a427` (tableau de 0.4).

Utiliser `install` (qui crée un fichier neuf), jamais `mv` ni `cp -p` depuis
`/tmp` : le fichier garderait le contexte SELinux de `/tmp` au lieu de celui de
`/usr/local/bin` (F.5). Test local de la commande (téléchargement et somme)
non fait ; la somme est celle du rôle, vérifiée par Ansible sur le LXC.

### F.3 Identifiants (fichier lisible par root seul)

Comme en 1.2, avec les valeurs de KeePass, jamais collées dans une
messagerie :

```bash
sudo install -d -m 0755 /etc/newt
sudo install -m 0600 /dev/null /etc/newt/env
sudo nano /etc/newt/env
```

```
PANGOLIN_ENDPOINT=https://pangolin.sylvain.cloud
NEWT_ID=<ID de KeePass>
NEWT_SECRET=<secret de KeePass>
```

### F.4 Service systemd, avec mise à jour automatique (1.4)

Le fichier est le rendu du modèle `newt.service.j2` du rôle avec
`newt_service_self_update: true` (commentaires du modèle omis). Le binaire vit
dans l'état du service (`/var/lib/newt/newt`, en réalité
`/var/lib/private/newt/newt`), `/usr/local/bin/newt` n'est que la graine.

`sudo nano /etc/systemd/system/newt.service` :

```ini
[Unit]
Description=Newt, Pangolin tunnel client
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/env
ExecStartPre=/bin/sh -c 'if [ ! -x /var/lib/newt/newt ] || [ /usr/local/bin/newt -nt /var/lib/newt/newt ]; then install -m 0755 /usr/local/bin/newt /var/lib/newt/newt; fi'
ExecStart=/var/lib/newt/newt
Restart=always
RestartSec=10
DynamicUser=yes
StateDirectory=newt
Environment=HOME=/var/lib/newt
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now newt
journalctl -u newt -n 20 --no-pager
```

Attendu, comme en 1.3 : `Tunnel connection to server established
successfully!`. Si `systemctl status newt` dit `status=203/EXEC` ou
`Permission denied` : c'est probablement SELinux (ou un fichier non exécutable), aller en F.5.

### F.5 SELinux : contextes et refus

Fedora est en **Enforcing** par défaut (pas les PC de Sylvain). Contextes que
la politique `targeted` donne par défaut (`matchpathcon <chemin>`, Fedora 44,
selinux-policy-targeted 44.11) :

| Chemin | Contexte par défaut | Commentaire |
|---|---|---|
| `/usr/local/bin/newt` | `bin_t` | règle `/usr/local/bin(/.*)?` ; `install` hérite du dossier |
| `/etc/newt/env` | `etc_t` | lu par systemd (`EnvironmentFile`) |
| `/etc/systemd/system/newt.service` | `systemd_unit_file_t` | idem pour un fichier créé par `nano` dans ce dossier |
| `/var/lib/private/newt/newt` (et `/var/lib/newt`, lien) | `var_lib_t` | règle `/var/lib(/.*)?` ; créé par `install` dans le dossier d'état, et le fichier temporaire de l'auto-mise à jour hérite aussi |

Donc **rien à installer ni à relabelliser dans le cas normal** : pas de
`semanage fcontext` nécessaire. Un contrôle sans effet s'il n'y a rien à
corriger (il n'écrit une ligne que s'il relabellise) :

```bash
sudo restorecon -Rv /usr/local/bin/newt /etc/newt /etc/systemd/system/newt.service /var/lib/private/newt
ls -Z /usr/local/bin/newt /var/lib/private/newt/newt
ps -eZ | grep newt
```

`restorecon` répare le seul vrai piège : un fichier déplacé depuis `/tmp` ou
`~` (`user_tmp_t`, `user_home_t`) que systemd refuse d'exécuter.

**Non testé : le domaine du processus.** Ni `bin_t` ni `var_lib_t` ne sont des
points d'entrée d'un domaine de service : systemd doit lancer Newt dans
`unconfined_service_t` (domaine non confiné du `targeted`), qui peut exécuter
et écrire dans `/var/lib` sans refus. À vérifier dans `ps -eZ | grep newt` :
`system_u:system_r:unconfined_service_t`. Si c'est `init_t`, ou si des refus
apparaissent (lecture ci-dessous), le plan B qui évite le sujet : étiqueter
l'état du service comme un binaire,

```bash
sudo semanage fcontext -a -t bin_t '/var/lib/private/newt(/.*)?'
sudo restorecon -RFv /var/lib/private/newt
sudo systemctl restart newt
```

(`semanage` est dans `policycoreutils-python-utils`, `sudo dnf install` si
absent), ou, plan C, retirer l'auto-mise à jour : `ExecStart=/usr/local/bin/newt`,
pas de `ExecStartPre`, mise à jour à la main (fin de 1.4).

Lire les refus :

```bash
sudo ausearch -m avc,user_avc -ts recent          # refus de la dernière heure
sudo ausearch -m avc -c newt -ts today
sudo journalctl -t setroubleshoot --since "-1h"   # si setroubleshoot est installé
```

Sans `auditd` (`ausearch` vide ou absent, `sudo dnf install audit`) :
`sudo journalctl -k --since "-1h" | grep -i avc`. Pour savoir si SELinux est la
cause : `sudo setenforce 0` (permissif jusqu'au redémarrage), relancer
`sudo systemctl restart newt`, puis **`sudo setenforce 1`** ; ne jamais
désactiver SELinux ni écrire de module `audit2allow` sans comprendre le refus.

### F.6 GNOME Remote Desktop et relais (Wayland)

Ce que la méthode de la fiche suppose : le **VNC de la session ouverte** de
GNOME Remote Desktop (service utilisateur), derrière le relais
`grd-vnc-relay` (grd n'offre que le TLS anonyme, que le navigateur refuse).
C'est la méthode du POC sur le poste de Sylvain (Fedora 44, GNOME, Wayland),
qui a marché le 08/11 : on garde celle-là.

- **RDP** : inutilisable depuis le navigateur sur GNOME (le client RDP du
  navigateur n'annonce pas RDPGFX, voir `support-a-distance.md`) ; pas de
  ressource RDP pour papa.
- Wayland : le partage de session par grd ne demande ni X11 ni portail. Limite
  déjà notée en 2a.6 : il n'existe que **session ouverte** ; écran verrouillé
  ou écran de connexion : non testé.
- Non testé : grd garde le mot de passe VNC dans le trousseau GNOME ; avec la
  connexion automatique le trousseau reste verrouillé et grd peut ne pas le
  lire (VNC refusé). Si le contrôle ci-dessous échoue après un redémarrage,
  c'est la première piste.

Même procédure que 2a, **à faire dans la session de papa, sans sudo** :

```bash
rpm -q gnome-remote-desktop python3 || sudo dnf install gnome-remote-desktop python3   # présents par défaut
```

puis **2a.2** (les commandes `grdctl vnc …`, mot de passe de KeePass), **2a.3**
(relais, somme `7e6dd112…e1867`, unité utilisateur, contrôle `[2]`) et **2a.5**
(consentement), telles quelles. Le pare-feu de 2a.4 (ufw) est remplacé par F.7.

### F.7 Pare-feu (firewalld)

- **Newt** : uniquement sortant (HTTPS et UDP vers Pangolin). firewalld ne
  filtre que l'entrant : **rien à ouvrir**.
- **Le VNC de grd écoute sur toutes les interfaces** (`0.0.0.0:5900`) et la
  zone `FedoraWorkstation` ouvre déjà `1025-65535` au réseau local : le 5900
  serait joignable depuis le Wi-Fi de la maison. Le relais, lui, n'écoute que
  sur `127.0.0.1:5901`, et Newt vise la boucle locale, que les zones ne
  filtrent pas. Même règle que `ansible/pc-support.yml` (rejet du 5900 dans
  chaque zone active) :

```bash
for z in $(sudo firewall-cmd --get-active-zones | awk '/^[^ ]/{print $1}'); do
  sudo firewall-cmd --permanent --zone="$z" --add-rich-rule='rule port port="5900" protocol="tcp" reject'
done
sudo firewall-cmd --reload
sudo firewall-cmd --list-rich-rules --zone=FedoraWorkstation
ss -ltn | grep -E ':(5900|5901)\b'    # 5901 sur 127.0.0.1 ; 5900 sur * est normal, la règle le garde
```

Si le PC change de zone (nouveau réseau Wi-Fi classé autrement), refaire la
boucle. `firewalld` arrêté (`systemctl is-active` ne dit pas `active`) :
démarrer le service avant, sinon le 5900 reste ouvert. Non testé : la règle
sur cette version de firewalld (c'est celle du playbook de Sylvain, testé sur
son poste).

### F.8 Vérification depuis chez soi

1. Pangolin → **Sites** : `pc-papa` **en ligne**, version de Newt affichée (1.20.0,
   qui monte seule ensuite, 1.4).
2. Téléphone en 4G : `https://<sous-domaine de PC Papa (VNC)>.sylvain.cloud`
   (voir `remote_support.tf`), SSO Pocket ID (groupe `support`), mot de passe
   VNC de KeePass : le bureau de papa, souris et clavier pilotables.
3. Depuis le Wi-Fi de la maison, `nc -zv <ip du PC> 5900` refusé.
4. Redémarrer le PC : Newt revient seul (`systemctl is-active newt`), le VNC à
   l'ouverture de la session ; puis refaire 2 le lendemain.

Pannes : celles de la section 4 ; en plus, « Connexion fermée avant que
l'authentification soit terminée » après un redémarrage : trousseau verrouillé
(F.6) ou relais arrêté (`systemctl --user status grd-vnc-relay`).

## 4. Vérification, sur place puis depuis chez soi

1. Sur le PC : Newt connecté (journal, section 1 ou 3.1) ; le site est en
   ligne dans Pangolin (Sites).
2. Depuis le téléphone (4G, Wi-Fi coupé) ou un autre PC : ouvrir
   `https://d-xxxxxx.sylvain.cloud`, SSO Pocket ID (compte du groupe
   `support`), puis mot de passe VNC. Attendu : le bureau, souris et clavier
   pilotables.
3. Depuis le Wi-Fi de la maison, un autre appareil : le port 5900 du PC est
   refusé (`nc -zv <ip du PC> 5900` depuis un Linux, ou un scanner de ports sur
   téléphone).
4. Redémarrer le PC : Newt revient seul ; le VNC revient à l'ouverture de la
   session (Debian) ou dès le démarrage (Windows, service).
5. Depuis chez soi, le lendemain : refaire 2.

Pannes : « Connexion fermée avant que l'authentification soit terminée » →
le serveur n'offre pas le mot de passe VNC (GNOME sans relais, MS Logon coché
chez UltraVNC, plugin de chiffrement) ; la page tourne sans fin → site hors
ligne (Newt arrêté, PC éteint) ou mauvais port dans la cible ; refus avant le
SSO → pays hors FR/DE (règles Pangolin).

## 5. Démontage d'un PC

Sur le PC, puis côté Pangolin.

Debian GNOME :

```bash
systemctl --user disable --now grd-vnc-relay
rm -f ~/.config/systemd/user/grd-vnc-relay.service ~/.local/bin/grd-vnc-relay
systemctl --user daemon-reload
grdctl vnc disable
systemctl --user disable --now gnome-remote-desktop
```

Debian X11 :

```bash
systemctl --user disable --now x11vnc
rm -f ~/.config/systemd/user/x11vnc.service ~/.vnc/passwd
systemctl --user daemon-reload
```

Newt (Debian ; Fedora : mêmes commandes, plus le dossier d'état et la règle de
pare-feu de F.7) :

```bash
sudo systemctl disable --now newt
sudo rm -rf /etc/systemd/system/newt.service /etc/systemd/system/newt.service.d /usr/local/bin/newt /etc/newt /var/lib/private/newt
sudo systemctl daemon-reload
# Fedora seulement : le VNC de grd et le rejet du 5900
sudo firewall-cmd --permanent --remove-rich-rule='rule port port="5900" protocol="tcp" reject'   # dans chaque zone active (--zone=…)
sudo firewall-cmd --reload
```

Le pare-feu ufw peut rester (il ne gêne rien) ou `sudo ufw disable`.

Windows (PowerShell administrateur) :

```powershell
cd "C:\Program Files\newt"; .\newt.exe stop; .\newt.exe remove
Remove-Item -Recurse -Force "C:\Program Files\newt", "$env:PROGRAMDATA\newt"
```

puis désinstaller UltraVNC (Paramètres → Applications).

Côté Pangolin : une PR qui retire l'entrée de `local.remote_desktops`, le
`pangolin_site` et ses deux sorties ; plan depuis `main` (destruction du site,
de la ressource, de sa cible, de ses règles et de sa liaison de rôle), puis
apply. Jamais à la main dans l'interface : le code de `main` le recréerait.
