# Accès de secours au LAN (WireGuard, sans Pangolin)

Une porte de secours vers le réseau local quand Pangolin ne répond plus :
un serveur WireGuard sur le LXC newt (192.168.1.200, rôle
`wireguard_rescue` de `lxc.yml`), joint directement par l'IP publique de la
maison sur **UDP 47913**, que la Bbox redirige. C'est le seul port entrant
de la maison ([ADR 0015](../adr/0015-acces-de-secours-wireguard.md)).

Le tunnel ne mène qu'au LAN `192.168.1.0/24`, jamais à Internet : le
téléphone et le portable gardent leur propre sortie. Les hôtes du LAN voient
arriver l'IP du LXC (masquerade) : SSH de la VM docker et du Pi (ufw ouvert
au LAN), interface de Proxmox, du NAS, de la Bbox. Les applis de la VM
docker n'ont pas de port publié : y passer par `ssh -L`.

## Quand s'en servir

- **Pangolin injoignable** ([pangolin-injoignable.md](pangolin-injoignable.md)) :
  plus de ressource privée, plus de CI, et il faut atteindre la maison
  depuis dehors (relancer Newt, lire un journal, éteindre proprement).
- Pas pour l'usage courant : le client Pangolin reste la voie normale.
  Tunnel fermé dès que l'incident est réglé.

## Se connecter

1. **Données mobiles (4G/5G)**, pas un Wi-Fi tiers : un réseau distant en
   `192.168.1.0/24` (Livebox, une autre Bbox) prend le pas sur le tunnel et
   le LAN de la maison devient injoignable.
2. Téléphone : appli WireGuard, activer `telephone`. Portable :
   `nmcli connection up portable`.
3. Atteindre le LAN :

   ```bash
   ping -c 3 192.168.1.200            # le LXC newt
   ssh sylvain@192.168.1.200          # le LXC (mise run ssh_newt l'est par le LAN)
   ssh sylvain@192.168.1.216          # la VM docker
   ```

4. Fermer le tunnel en fin d'incident (`nmcli connection down portable`).

## Vérifier

- Côté client : `sudo wg show` (portable) ou l'appli : une « latest
  handshake » de moins de deux minutes et des octets reçus.
- Côté LXC (par le LAN ou le tunnel) :

  ```bash
  sudo wg show wg-rescue                         # pairs, dernière poignée de main
  sudo nft list table inet wireguard_rescue      # forward en policy drop, masquerade
  cat /proc/sys/net/ipv4/ip_forward              # 1
  sudo systemctl start wireguard-rescue-check    # pousse au moniteur « Accès de secours »
  ```

- Aucune poignée de main : l'IP publique a changé (`curl -4 ifconfig.me`
  depuis la maison contre `home_ip` de `ansible/secrets.sops.yaml`), la
  redirection de la Bbox a disparu (réinitialisation, mise à jour), ou le
  LXC est arrêté (Proxmox, `pct status 200`).

## Couper vite

Du plus rapide au plus durable :

1. Sur le LXC : `sudo systemctl disable --now wg-quick@wg-rescue`
   (interface, règles et forwarding tombent ensemble ; le prochain
   `lxc.yml` le relance tant que la variable est à `true`). Depuis le shell
   de Proxmox, sans SSH : `pct exec 200 -- systemctl disable --now wg-quick@wg-rescue`.
2. Sur la Bbox : désactiver la règle de redirection `wireguard-secours`
   (plus rien n'arrive au LXC).
3. Durable : `wireguard_rescue_enabled: false` dans
   `ansible/host_vars/newt-lxc/variables.yaml`, puis
   `ansible-playbook lxc.yml --tags wireguard_rescue` (configuration, clé
   privée, règles et vérification supprimées du LXC ; clés gardées dans
   SOPS). Le moniteur « Accès de secours » passe au rouge sous deux jours :
   `active = false` dans `tofu/pangolin_config/cron_wireguard_rescue.tf`,
   puis `tofu apply`.

## Révoquer un pair

Téléphone ou portable perdu ([perte-cle-ou-poste.md](perte-cle-ou-poste.md)) :

1. Tout de suite, sur le LXC : `sudo wg set wg-rescue peer <clé publique> remove`
   (clé publique dans `host_vars/newt-lxc`) ; tient jusqu'au prochain
   passage d'Ansible.
2. Retirer son entrée de `wireguard_rescue_peers`
   (`ansible/host_vars/newt-lxc/variables.yaml`) et ses clés de SOPS :

   ```bash
   cd ansible
   sops unset secrets.sops.yaml '["wireguard_rescue_peer_keys"]["telephone"]'
   ansible-playbook lxc.yml --tags wireguard_rescue --check --diff
   ansible-playbook lxc.yml --tags wireguard_rescue
   ```

3. `sudo wg show wg-rescue` ne le liste plus.

## Ajouter ou remplacer un pair

Clés générées et rangées sans jamais être affichées (`wg` du paquet
`wireguard-tools` du poste) ; seule la clé publique sort, pour
`host_vars/newt-lxc` :

```bash
cd ansible
priv=$(wg genkey); psk=$(wg genpsk)
printf '%s' "$priv" | wg pubkey        # -> public_key du pair dans host_vars/newt-lxc
printf '{"private_key":"%s","preshared_key":"%s"}' "$priv" "$psk" |
  sops set --value-stdin secrets.sops.yaml '["wireguard_rescue_peer_keys"]["telephone"]'
unset priv psk
```

Nouveau pair : une entrée `name`/`address` (adresse libre de
`10.77.0.0/24`, pas `.1`)/`public_key` dans `wireguard_rescue_peers`. Puis
`lxc.yml --tags wireguard_rescue` et la configuration du pair (ci-dessous).

Clé du serveur (rotation, fuite) : `printf '"%s"' "$(wg genkey)" | sops set
--value-stdin secrets.sops.yaml '["wireguard_rescue_server_private_key"]'`,
`lxc.yml --tags wireguard_rescue`, puis réimporter **tous** les pairs. Date
dans `secrets-rotation.yaml`.

## Rendre et importer la configuration des pairs

```bash
cd ansible
ansible-playbook wireguard-rescue-peers.yml          # -e wireguard_rescue_peer_only=telephone pour un seul
qrencode -t ansiutf8 < "$XDG_RUNTIME_DIR/wireguard-rescue/telephone.conf"
nmcli connection import type wireguard file "$XDG_RUNTIME_DIR/wireguard-rescue/portable.conf"
nmcli connection modify portable connection.autoconnect no
rm -r "$XDG_RUNTIME_DIR/wireguard-rescue"
```

Le playbook ne touche aucun hôte : il recalcule les clés publiques depuis
SOPS (et s'arrête si `host_vars/newt-lxc` ne correspond plus), et écrit un
fichier `0600` par pair sous `$XDG_RUNTIME_DIR` (tmpfs). Téléphone : appli
WireGuard, « + », « Scanner un code QR », nom `telephone`. Le point
d'entrée est `home_ip` ; `-e wireguard_rescue_endpoint=<IP>` pour une
autre.

## Mise en place (une fois)

1. Modules noyau sur Proxmox (le LXC non privilégié ne peut pas les
   charger) : `ansible-playbook pve.yml --tags wireguard`.
2. Moniteur : `tofu apply` dans `tofu/pangolin_config`
   (`cron_wireguard_rescue.tf`).
3. Serveur : `ansible-playbook lxc.yml --tags wireguard_rescue --check --diff`,
   puis sans `--check`.
4. **Bbox** (`https://mabbox.bytel.fr` ou `http://192.168.1.254`, mot de
   passe d'administration de la box) ; libellés de l'interface actuelle, à
   confirmer au premier passage :
   1. **Réseau local → DHCP** : vérifier que 192.168.1.200 est hors de la
      plage DHCP (ou réservée au LXC), sinon un autre appareil peut la
      prendre.
   2. **Services de la Box → Redirection de ports** (NAT/PAT), « Ajouter une
      règle » : nom `wireguard-secours`, protocole **UDP**, port externe
      **47913**, appareil ou IP de destination **192.168.1.200**, port
      interne **47913**, règle activée. Enregistrer.
   3. **Sécurité → Pare-feu** : au niveau par défaut, une redirection
      ouvre son port ; un niveau « élevé » ou une règle sortante peut le
      bloquer, à vérifier si aucune poignée de main n'arrive.
   4. Rien d'autre : ni DMZ, ni UPnP, ni IPv6 pour ce port.
5. Pairs : section précédente, puis un essai **depuis la 4G** (Wi-Fi coupé) :
   `ping 192.168.1.200` et `sudo wg show wg-rescue` sur le LXC (poignée de
   main du pair).

## Prévention

- Le moniteur « Accès de secours » (chaque matin, `wireguard-rescue-check.timer`)
  ne voit que le LXC : interface, port, règles, forwarding. La Bbox et
  l'IP publique ne se vérifient qu'en se connectant : un essai depuis la 4G
  après chaque réinitialisation ou mise à jour de la Bbox, et au moins une
  fois par trimestre.
- Le serveur filtre lui-même (forward en `policy drop` hors pair → LAN) :
  un `AllowedIPs = 0.0.0.0/0` côté client ne donne pas Internet par la
  maison.
