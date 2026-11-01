# DNS : plus d'Internet, ou un site ne charge plus (Blocky)

Le DNS de la maison passe par **Blocky** (rôle `ansible/roles/blocky`,
[ADR 0012](../adr/0012-filtrage-dns-blocky.md)), en deux instances que le
DHCP de la Bbox annonce toutes les deux :

| Instance | IP | Déployée par | Forme |
|---|---|---|---|
| Raspberry Pi | 192.168.1.96 | `pi.yml` (CI au merge) | conteneur `dc@blocky`, `/opt/apps/blocky` |
| LXC newt | 192.168.1.200 | `lxc.yml` (à la main) | binaire, `blocky.service`, `/etc/blocky` |

Chacune résout en DNS-over-TLS chez Quad9 et Mullvad, bloque les listes
HaGeZi Pro (`ads`) et HaGeZi TIF medium (`threats`), rafraîchies chaque jour,
renvoie le domaine `lan` et la zone inverse à la Bbox (192.168.1.254), et ne
journalise aucune requête.

## Contournement d'urgence

Plus rien ne résout et pas le temps de chercher : **remettre le DNS de la
Bbox** dans son DHCP (voir « Bascule du DHCP de la Bbox », retour arrière),
puis renouveler le bail des appareils (Wi-Fi coupé puis rallumé). Internet
revient, sans filtrage. Un seul poste : lui donner `192.168.1.254` comme DNS
à la main.

## Symptôme

- « Plus d'Internet » sur tous les appareils, alors que la Bbox est
  synchronisée (une IP en ping marche : `ping 9.9.9.9`, mais pas
  `ping example.com`).
- Un site ou une appli ne charge plus, ou une partie seulement (connexion à
  la banque, lien d'un e-mail, paiement) : un domaine bloqué à tort.
- Moniteur Uptime Kuma « DNS Raspberry Pi » ou « DNS LXC newt » rouge
  (Telegram et ntfy) : la vérification locale de l'hôte (`blocky-check.timer`,
  toutes les 5 minutes) a échoué, ou ne pousse plus.

## Diagnostic

1. Les deux instances, depuis un poste du LAN :

   ```bash
   dig +short @192.168.1.96 example.com     # une IP : le Pi répond
   dig +short @192.168.1.200 example.com    # une IP : le LXC répond
   dig +short @192.168.1.254 example.com    # la Bbox, sans Blocky
   ```

   Une seule muette : les clients basculent sur l'autre, rien d'urgent (le
   moniteur le dit). Les deux muettes : contournement ci-dessus, puis
   l'étape 2 sur chaque hôte.

2. Sur l'hôte en panne (`mise run ssh_pi`, `mise run ssh_newt`) :

   ```bash
   # Pi
   systemctl --user status dc@blocky
   docker logs --tail 50 blocky
   # LXC
   systemctl status blocky
   journalctl -u blocky -n 50 --no-pager
   # les deux : la dernière vérification et sa raison (les lignes
   # event=blocky_stats sont les compteurs de la carte Blocky de Homepage)
   journalctl -u blocky-check -n 5 --no-pager
   ```

   Au démarrage, Blocky écrit `import succeeded count=…` par liste. Une liste
   injoignable reprend la copie de son dernier téléchargement
   (`cachePath`) ; sans copie, Blocky sert sans cette liste, et la
   vérification pousse « … n'est pas bloqué (listes non chargées ?) ».

3. Un domaine bloqué à tort : quelle liste le bloque ?

   ```bash
   dig +short @192.168.1.200 domaine.example   # 0.0.0.0 = bloqué
   # sur le LXC (l'API n'écoute que sur 127.0.0.1)
   blocky_bin=$(ls /usr/local/lib/blocky/v*/blocky)
   $blocky_bin --config /etc/blocky/config.yml query domaine.example
   # sur le Pi
   docker exec blocky /app/blocky query domaine.example
   ```

   `reason: BLOCKED (ads: *.domaine.example)` donne la liste et l'entrée. Une
   réponse vide avec `REBIND` : protection contre le DNS rebinding, un nom
   public qui pointe dans le LAN (voir Réparation).

## Réparation

- **Débloquer un domaine** : l'ajouter à `blocky_allowlist`
  (`ansible/roles/blocky/defaults/main.yml`, `*.` devant pour ses
  sous-domaines aussi), PR, merge (déploie le Pi), puis
  `ansible-playbook lxc.yml --tags blocky` (le LXC). En attendant, sur le poste
  concerné seulement, DNS `192.168.1.254` à la main.
- **Un nom public qui pointe dans le LAN** (un A de `tofu/dns` vers une IP
  192.168.x, comme `media.sylvain.cloud`) : l'ajouter à
  `blocky_rebinding_allowed_domains`, même chemin.
- **Instance arrêtée** : `systemctl --user restart dc@blocky` (Pi),
  `sudo systemctl restart blocky` (LXC). Une configuration refusée au démarrage
  se lit dans les logs ; sur le LXC, Ansible la valide (`blocky validate`)
  avant de la poser.
- **Listes à recharger tout de suite** (après un ajout à l'allowlist, le
  redémarrage suffit) : `docker exec blocky /app/blocky lists refresh` (Pi),
  `$blocky_bin --config /etc/blocky/config.yml lists refresh` (LXC, `blocky_bin`
  de l'étape 3 du diagnostic).

## Vérification

```bash
dig +short @192.168.1.96 example.com            # une IP
dig +short @192.168.1.96 googlesyndication.com  # 0.0.0.0
dig +short @192.168.1.200 pi.lan                # 192.168.1.96 (la Bbox)
sudo systemctl start blocky-check.service && journalctl -u blocky-check -n 1 --no-pager
```

Le moniteur repasse vert au push suivant (5 minutes au plus).

## Bascule du DHCP de la Bbox

Faite par Sylvain dans l'interface de la Bbox (https://mabbox.bytel.fr ou
http://192.168.1.254), une fois les deux instances déployées et vérifiées
(Vérification ci-dessus, depuis un poste).

1. Réglages du **serveur DHCP** du réseau local (menu « Réseau local » ou
   « Services de la Box » → « DHCP » selon le modèle, intitulé à confirmer) :
   DNS primaire `192.168.1.200` (LXC newt), DNS secondaire `192.168.1.96`
   (Pi). Noter avant les valeurs d'origine (en général la Bbox elle-même).
2. Vérifier que le Pi et le LXC ont une IP fixe (bail réservé dans la Bbox
   pour le Pi, IP statique du LXC dans `tofu/proxmox`) : une IP de DNS qui
   change, c'est toute la maison sans DNS.
3. Renouveler le bail d'un poste (Wi-Fi coupé puis rallumé), puis
   `resolvectl status` (Linux) ou les détails du Wi-Fi (téléphone) : les deux
   IP de Blocky.
4. **IPv6** : la Bbox annonce aussi son propre DNS en IPv6 (RA/DHCPv6), que
   les clients peuvent préférer, sans filtrage. Vérifier sur un poste
   (`resolvectl status` : un serveur `2a01:…` ou `fe80::…` à côté des IPv4).
   S'il y est, chercher dans la Bbox le réglage du DNS IPv6 annoncé (à
   confirmer selon le modèle) ; sinon le filtrage n'est que partiel, décision
   à prendre (couper l'IPv6 du LAN, ou l'accepter).

**Retour arrière** : remettre les DNS d'origine notés à l'étape 1 (ou « DNS
de la Bbox »), puis renouveler les baux. Blocky peut rester déployé : plus
aucun client ne l'interroge.

## Téléphone en 4G (client Pangolin)

Hors de la maison, le téléphone passe par Blocky si le client Pangolin est
connecté et réglé ainsi (appli Pangolin Android, Réglages) :

- « Enable Aliases (DNS Override) » : activé ;
- « DNS Over Tunnel » : activé ;
- « Primary Upstream DNS Server » : `192.168.1.200` (ressource privée `dns`,
  `tofu/pangolin_config/private_resources.tf`, TCP et UDP 53) ;
- « Secondary Upstream DNS Server » : `192.168.1.96` (le Pi, par la ressource
  `pi`, UDP seulement).

Le serveur Pangolin ne pousse aucun réglage DNS à ses clients : c'est à faire
sur chaque téléphone. Le « DNS privé » d'Android doit rester sur
« Automatique » ou « Désactivé » : un fournisseur DNS privé passerait à côté.
Les deux DNS passent par le Newt du LXC : LXC éteint, le téléphone n'a plus de
DNS tant que le client Pangolin est connecté (le déconnecter).

## Prévention

- Une montée de version de Blocky (Renovate, groupe `blocky`) change l'image
  du Pi **et** le binaire du LXC, avec `blocky_binary_sha256` : le merge
  déploie le Pi, `lxc.yml --tags blocky` le LXC. Vérifier que le Pi répond
  (`dig @192.168.1.96`) avant de lancer `lxc.yml` : les deux instances ne
  tombent jamais ensemble sur une version cassée.
- Les listes HaGeZi sont tirées de GitHub une fois par jour. Une liste
  injoignable, disparue ou renommée peut continuer d'être servie depuis sa
  copie sur disque (`cachePath`) sans que rien n'alerte : la vérification
  ne teste qu'un nom de la liste `ads`, et ne voit donc qu'une liste `ads`
  jamais chargée, rien pour `threats`. Après une montée de version ou une
  longue coupure, lire les `import succeeded count=…` dans les logs.
