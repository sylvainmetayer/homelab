# 0015. Accès de secours au LAN par WireGuard, sans Pangolin

- **Statut** : proposée
- **Date** : 2026-10-28
- **Note** : non mise en œuvre ; PR #948 écrite puis fermée le 2026-10-29,
  le besoin réel restant à établir (un port entrant est peut-être excessif).

## Contexte

Tout accès distant passe par Pangolin ([0002](0002-pangolin-seule-entree-publique.md)) :
Pangolin en panne, plus rien n'atteint la maison de dehors. Il faut une
porte de secours, la plus petite possible, qui n'en dépende pas.

## Décision envisagée

- **WireGuard du noyau sur le LXC newt** (rôle `wireguard_rescue`), UDP 47913
  redirigé par la Bbox vers 192.168.1.200 : **seul port entrant de la maison**.
- Deux pairs, clés et `preshared_key` dans SOPS ; le tunnel ne mène qu'au LAN
  (forward nftables en `policy drop` hors pair → LAN, masquerade), **jamais
  Internet**. Coupé d'une variable (`wireguard_rescue_enabled`), vérifié
  chaque matin côté LXC (moniteur « Accès de secours »).

## Alternatives écartées

- **wireguard-go ou boringtun** : dans un LXC non privilégié il faut
  `/dev/net/tun`, un passage de périphérique réservé à `root@pam` ; le module
  noyau de l'hôte suffit, chargé par `pve.yml`.
- **Sur la VM docker** : le pare-feu et les applis y sont ; le LXC n'a que Newt.
- **Second Pangolin, Tailscale, SSH exposé** : un service ou un tiers de plus,
  ou un port TCP connu et scanné, pour une porte qui sert rarement.

## Conséquences

- La maison a un port ouvert : silencieux sans clé, mais à garder unique.
- Il tombe avec le LXC, Proxmox ou un changement de `home_ip` ; la
  redirection de la Bbox ne se vérifie qu'à la main.
- Un réseau distant en 192.168.1.0/24 masque le LAN : se connecter en 4G/5G.

## Liens

PR #948 (fermée, non mergée : rôle `wireguard_rescue`, runbook `acces-de-secours.md`).
