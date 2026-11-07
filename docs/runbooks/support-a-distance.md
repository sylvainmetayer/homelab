# Support à distance (POC sur le poste) : mise en place, test, démontage

Prise en main du poste de Sylvain (Fedora, GNOME) depuis un navigateur, par
les ressources Pangolin « PC Sylvain (VNC) » et « PC Sylvain (RDP) ». Newt
tourne sur le poste (site `pc-sylvain`) et vise la boucle locale. Côté
Pangolin : `tofu/pangolin_config/remote_support.tf`. Côté poste :
[`ansible/pc-support.yml`](../../ansible/pc-support.yml), **jamais lancé par la
CI** (procédure, pas un incident).

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
- La ressource VNC ouvre la session en cours, souris et clavier compris (le
  client VNC du navigateur n'a pas de presse-papiers).
- La ressource RDP ouvre l'écran de connexion de GDM, y compris juste après
  un redémarrage du poste, avant toute connexion locale.
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

Une PR qui revient sur les commits du POC (`feat(support)` et les deux
`fix(support)`), **pas sur le bump du provider** en `1.7.0-sylvain.5` arrivé
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
  `systemctl --user status gnome-remote-desktop` inactifs ; `sudo ss -ltnp`
  ne montre plus rien sur 5900 ni 3389.

Les sous-domaines `d-tyl53u` et `d-nb335s` restent dans les journaux
Certificate Transparency. Ils sont neutres et ne disent rien du poste.
