# 0015. Accès de secours au LAN par WireGuard, sans Pangolin

- **Statut** : rejetée (2026-11-07 ; proposée le 2026-10-28, #948 fermée le 2026-10-29)
- **Date** : 2026-11-07

## Contexte

Tout accès distant passe par Pangolin ([0002](0002-pangolin-seule-entree-publique.md)) :
Pangolin en panne, plus rien n'atteint la maison de dehors. Il faut une
porte de secours, la plus petite possible, qui n'en dépende pas.

## Décision

- **WireGuard du noyau sur le LXC newt** (rôle `wireguard_rescue`), UDP 47913
  redirigé par la Bbox vers 192.168.1.200 : **seul port entrant de la maison**.
- Deux pairs, clés et `preshared_key` dans SOPS ; le tunnel ne mène qu'au LAN
  (forward nftables en `policy drop` hors pair → LAN, masquerade), **jamais
  Internet**. Coupé d'une variable (`wireguard_rescue_enabled`), vérifié
  chaque matin côté LXC (moniteur « Accès de secours »).

## Alternatives écartées

- **wireguard-go ou boringtun** : dans un LXC non privilégié il faut
  `/dev/net/tun`, un passage de périphérique réservé à `root@pam` ; le module
  noyau de l'hôte suffit, à charger par `pve.yml`.
- **Sur la VM docker** : le pare-feu et les applis y sont ; le LXC n'a que Newt.
- **Second Pangolin, Tailscale** : un service ou un tiers de plus, pour une
  porte qui sert rarement.
- **SSH exposé** : un port TCP connu, scanné ; WireGuard ne répond pas sans clé.

## Conséquences

- La maison a un port ouvert : silencieux sans clé, mais à garder unique.
- Il tombe avec le LXC, Proxmox ou un changement de `home_ip` ; la
  redirection de la Bbox ne se vérifie qu'à la main.
- Un réseau distant en 192.168.1.0/24 masque le LAN : se connecter en 4G/5G.

## Pourquoi rejetée

Décision de Sylvain, le 2026-11-07. Le besoin est déjà couvert par les
runbooks, sans port entrant :

- Pangolin ou flip hors d'atteinte : la console Hetzner
  ([pangolin-injoignable.md](../runbooks/pangolin-injoignable.md),
  [flip-injoignable.md](../runbooks/flip-injoignable.md)).
- Proxmox verrouillé : session root, Shell web, console physique
  ([proxmox-injoignable-apres-durcissement.md](../runbooks/proxmox-injoignable-apres-durcissement.md)).
- Box remplacée, Pi mort, maison perdue : écran et clavier sur place, puis
  la console Hetzner ([bbox-remplacee.md](../runbooks/bbox-remplacee.md),
  [pi-mort.md](../runbooks/pi-mort.md),
  [perte-totale-maison.md](../runbooks/perte-totale-maison.md)).

Une porte d'entrée de plus serait une surface à maintenir (clés, redirection
de la Bbox, rôle, moniteur) pour un besoin rare. La maison garde zéro port
entrant. Reste : sans Pangolin, rien n'atteint le LAN de dehors ; il faut
être sur place.

## Liens

PR #948 (fermée, non mergée : rôle `wireguard_rescue`, runbook `acces-de-secours.md`).
