# Support à distance (POC sur le poste) : mise en place, test, démontage

Prise en main du poste de Sylvain (Fedora, GNOME) depuis un navigateur, par
les ressources Pangolin « PC Sylvain (VNC) » et « PC Sylvain (RDP) ». Newt
tourne sur le poste (site `pc-sylvain`) et vise la boucle locale. Côté
Pangolin : `tofu/pangolin_config/remote_support.tf`. Côté poste :
[`ansible/pc-support.yml`](../../ansible/pc-support.yml), **jamais lancé par la
CI** (procédure, pas un incident). Pour un autre PC (Debian, Windows), sans
Ansible : [support-a-distance-famille.md](support-a-distance-famille.md) ;
sa section 2a est aussi l'équivalent manuel du playbook pour ce poste.

## Limites de GNOME devant le navigateur

- **VNC** : GNOME Remote Desktop n'offre que le type de sécurité 18 (TLS
  anonyme), que le client VNC du navigateur ne négocie pas (« Connexion fermée
  avant que l'authentification soit terminée »). Le playbook installe donc un
  relais local, `grd-vnc-relay` (service utilisateur, `127.0.0.1:5901`), qui
  ouvre ce TLS vers grd (5900) et passe l'authentification VNC classique
  telle quelle ; la cible Pangolin vise 5901.
- **RDP** : grd ferme toute connexion d'un client sans pipeline graphique
  (RDPGFX) : « Client did not advertise support for the Graphics Pipeline »
  dans `journalctl -u gnome-remote-desktop`. Le client RDP du navigateur
  (IronRDP) ne l'annonce pas : la ressource RDP ne mène nulle part sur un
  GNOME récent, seul un client natif (Remmina, mstsc) y arrive.

## Mise en place

1. Apply de `tofu/pangolin_config` depuis `main` : il crée le site, les deux
   ressources, leurs cibles, les règles FR/DE, le rôle et le groupe Pocket ID
   `support`.
2. S'ajouter au groupe Pocket ID `support`, puis se reconnecter au mur SSO
   (les rôles Pangolin sont réécrits à chaque connexion).
3. Depuis `ansible/` : `ansible-playbook pc-support.yml -K`. Il demande le mot
   de passe VNC (seuls ses 8 premiers caractères comptent) et l'identifiant et
   le mot de passe RDP, à garder dans KeePass. Relancer le playbook les
   redemande et redémarre GNOME Remote Desktop, ce qui coupe une session en
   cours.

Si firewalld est arrêté, le playbook saute le pare-feu et l'annonce : 5900 et
3389 restent alors joignables depuis le réseau local. Une fois firewalld
démarré, relancer avec `--tags firewall`.

## Vérification

- Le site `pc-sylvain` est en ligne dans Pangolin, et `systemctl status newt`
  est actif.
- `systemctl --user status grd-vnc-relay` actif. La ressource VNC ouvre la
  session en cours, souris et clavier compris (le client VNC du navigateur
  n'a pas de presse-papiers). Un refus du relais s'écrit dans
  `journalctl --user -u grd-vnc-relay`.
- `sudo grdctl --system status` : `Username` renseigné sous `RDP:`. Le
  navigateur n'ira pas plus loin (section précédente).
- Depuis un autre appareil du réseau local, `nc -zv <ip du poste> 5900` et
  `nc -zv <ip du poste> 3389` sont refusés.
- Poste éteint une heure : aucune alerte « Site hors ligne ». Les règles
  `resource_unhealthy` et `resource_toggle` couvrent encore ces ressources :
  si elles sonnent, il faut les restreindre à une liste.

## Démontage

Le poste d'abord : sinon Newt réessaie en boucle de joindre un site supprimé.

### 1. Sur le poste

```bash
# Newt
sudo systemctl disable --now newt
sudo rm -rf /etc/systemd/system/newt.service /usr/local/bin/newt /etc/newt
sudo systemctl daemon-reload

# Relais VNC
systemctl --user disable --now grd-vnc-relay
rm -f ~/.config/systemd/user/grd-vnc-relay.service ~/.local/bin/grd-vnc-relay
systemctl --user daemon-reload

# GNOME Remote Desktop : VNC (service utilisateur), RDP (service système)
grdctl vnc disable
systemctl --user disable --now gnome-remote-desktop
sudo grdctl --system rdp disable
sudo grdctl --system rdp clear-credentials   # sinon, disable suffit
sudo systemctl disable --now gnome-remote-desktop
sudo rm -f /var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/tls.{crt,key}

# Pare-feu : pour chaque zone de `firewall-cmd --get-active-zones`
zone=FedoraWorkstation
for p in 5900 3389; do
  sudo firewall-cmd --permanent --zone="$zone" \
    --remove-rich-rule="rule port port=\"$p\" protocol=\"tcp\" reject"
done
sudo firewall-cmd --reload
```

Le mot de passe VNC reste dans le trousseau GNOME ; sans VNC actif, il ne sert
plus à rien.

### 2. Côté Pangolin

Une PR qui revient sur les commits du POC (`feat(support)`, `fix(support)`,
`docs(support)`), **pas sur le bump du provider** en `1.7.0-sylvain.5` arrivé
dans la même PR. Après le merge, un plan depuis `main` doit annoncer
**15 destructions et 6 modifications** (l'alerte « Site hors ligne » revient à
tous les sites, le `role_mapping` de Pocket ID perd `support`, quatre compteurs
d'audit), puis l'apply.

Ne rien supprimer à la main, ni dans l'interface ni par `tofu destroy -target` :
le code de `main` le recréerait au plan suivant.

### Vérification

- Plus de site `pc-sylvain` ni de ressource « PC Sylvain » dans Pangolin ;
  le plan suivant est vide.
- Sur le poste : `systemctl status newt gnome-remote-desktop` et
  `systemctl --user status gnome-remote-desktop grd-vnc-relay` inactifs ;
  `sudo ss -ltnp` ne montre plus rien sur 5900, 5901 ni 3389.

Les sous-domaines `d-tyl53u` et `d-nb335s` restent dans les journaux
Certificate Transparency. Ils sont neutres et ne disent rien du poste.
