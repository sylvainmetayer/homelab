# La Bbox est remplacée

La Bbox (192.168.1.254) est la passerelle du LAN, son DHCP et le résolveur des
noms locaux. Sa configuration vit dans son interface, **hors du dépôt** : tout
ce qui suit est à refaire à la main, avec les valeurs que le dépôt suppose.

## Symptôme

- Box changée (panne, nouvel abonnement) ou réinitialisée.
- Après : plus d'Internet, ou Internet mais plus de filtrage, des hôtes qui
  changent d'IP, Immich qui redemande le SSO à la maison, `pi.lan` ou
  `nas.lan` qui ne résolvent plus.

## Diagnostic

Ce que le dépôt suppose de la box :

| Réglage | Valeur attendue | Qui en dépend |
|---|---|---|
| Réseau local | `192.168.1.0/24`, passerelle et DHCP en `192.168.1.254` | **tous** les hôtes (`tofu/proxmox` : VM et LXC à IP fixe avec cette passerelle) |
| DNS annoncés par le DHCP | `192.168.1.200` puis `192.168.1.96` | filtrage Blocky ([dns-blocky.md](dns-blocky.md)) ; bascule non constatée au 05/11 ([ADR 0012](../adr/0012-filtrage-dns-blocky.md)), à relire dans la Bbox |
| Baux réservés | Pi `192.168.1.96`, NAS `192.168.1.137` (à vérifier), imprimante | DNS, Immich, `known_hosts`, DNS public de `tofu/dns` |
| Hôtes à IP fixe hors DHCP | VM docker `.216`, LXC `.200`, hôte Proxmox `.26` | à exclure de la plage DHCP (à vérifier) |
| Redirections de ports | **aucune** | ([ADR 0015](../adr/0015-acces-de-secours-wireguard.md) n'est pas mise en œuvre) |
| IP publique | stable ou non : à vérifier chez l'opérateur | `home_ip`, plus bas |

Si la nouvelle box ne sait pas servir un autre réseau que le sien, ne pas
changer de plage : refaire `192.168.1.0/24` (sinon il faut toucher
`tofu/proxmox`, l'inventaire, Blocky, Pangolin, `known_hosts`…).

## Réparation

1. **Réseau local** : plage et passerelle ci-dessus. Les hôtes à IP fixe
   n'attendent rien du DHCP et reviennent seuls une fois la passerelle là.
2. **Réservations** : une par MAC, donc à refaire pour chaque appareil (la box
   neuve ne connaît rien) : Pi, NAS, imprimante, au minimum. Relever les MAC
   dans le tableau de bord de la box ou sur l'appareil. Un appareil qui prend
   une autre IP que celle du dépôt casse son rôle (DNS, NFS, Newt).
3. **DNS du DHCP** : la procédure de bascule de
   [dns-blocky.md](dns-blocky.md) (« Bascule du DHCP de la Bbox ») : primaire
   `192.168.1.200`, secondaire `192.168.1.96`, puis renouveler les baux.
   Sans cela, tout marche mais sans filtrage, avec le DNS de la box.
   Vérifier aussi l'IPv6 (étape 4 de cette procédure).
4. **Noms locaux** : Blocky renvoie le domaine `lan` et les noms sans domaine
   à la box (`pi.lan`, `data.lan`…). Il faut que la box nomme à nouveau les
   appareils (nom d'hôte du bail). `pve.lan`, `docker.lan`, `nas.lan` et
   `newt-lxc.lan` sont déclarés dans Blocky et n'en dépendent pas.
5. **IP publique** : relever la nouvelle (ce que voit un site « quelle est mon
   IP »). Si elle a changé, c'est `home_ip` :
   - remplacer `home_ip` dans les **deux** fichiers SOPS
     (`secrets/secrets.sops.yaml` pour Tofu, `secrets/ansible.sops.yaml` pour
     Ansible), [rotation-des-secrets.md](rotation-des-secrets.md) pour la
     méthode (`sops set`, commit dans le sous-module, bump par PR) ;
   - `tofu apply` dans `tofu/pangolin_config` : les règles `ACCEPT` de
     priorité 9 d'Immich (et de son kiosque), Dawarich et TREK suivent ([acces-mobile.md](../acces-mobile.md)) ;
   - `ansible-playbook pangolin.yaml --check --diff` puis sans `--check` (liste
     blanche de CrowdSec, [crowdsec.md](crowdsec.md)).

   Tant que ce n'est pas fait, l'appli mobile d'Immich à la maison retombe sur
   le SSO. Pire : **l'ancienne IP, réattribuée, garde l'accès sans SSO**.
   Rien ne met `home_ip` à jour tout seul (pas de DNS dynamique dans le
   dépôt) : une IP qui change à chaque coupure ne convient pas à cette règle.
6. **Wi-Fi** : nom et mot de passe sont à retaper sur chaque appareil (rien
   dans le dépôt). Garder le même nom et le même mot de passe évite de tout
   reconfigurer. Attention au Wi-Fi invité : tout appareil derrière la box,
   invité compris, est « la maison » pour `home_ip`.
7. **Autres** : ressource privée `bbox-internal.sylvain.cloud` (interface de
   la box, `192.168.1.254` dans `private_resources.tf`) et celle de l'imprimante :
   à retester. Jetons d'API OVH ou Hetzner restreints par IP, s'il y en a : à
   vérifier chez eux.

## Vérification

- Depuis un poste : `ping 192.168.1.254`, `dig +short @192.168.1.200
  example.com`, `dig +short @192.168.1.96 example.com`, puis `resolvectl status`
  (les deux IP de Blocky, aucun DNS inattendu).
- Les hôtes sont à leur IP : `docker.lan`, `pve.lan` répondent ; moniteurs
  « DNS Raspberry Pi » et « DNS LXC newt » verts.
- Immich sur le Wi-Fi de la maison s'ouvre sans SSO ; hors Wi-Fi, avec lui.
- Les sites Pangolin restent en ligne : les Newt sont des tunnels sortants,
  la box ne redirige rien.

## Prévention

- Noter, hors du dépôt public, la liste des baux réservés (MAC et IP) et un
  export de la configuration de la box si elle le permet (à vérifier).
- L'aide-mémoire de ce que le dépôt suppose est le tableau « Diagnostic » :
  le tenir à jour quand un hôte change d'IP.
