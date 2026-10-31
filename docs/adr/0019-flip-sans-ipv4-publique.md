# 0019. flip reste sans IPv4 publique

- **Statut** : acceptée
- **Date** : 2026-10-31

## Contexte

flip (Flip Planning, Promptoramix) n'a ni IPv4 ni IPv6 publique
(`public_net` de `tofu/pangolin/flip.tf`). Il dépend de Pangolin pour tout :

- sortie sur Internet : route `0.0.0.0/0` du réseau privé vers Pangolin
  (`hcloud_network_route.nat`, `tofu/pangolin/nat.tf`), MASQUERADE du rôle
  `nat_gateway`, route par défaut et DNS tenus par le rôle `nat_client` ;
- SSH : rebond par Pangolin (ProxyCommand de `ansible/inventory/hetzner.py`) ;
- publication : son propre Newt (site `flip`), qui sort lui aussi par le NAT.

## Décision

Pas d'IPv4 publique sur flip : le NAT par Pangolin et le rebond SSH restent.

## Alternatives écartées

- **IPv4 publique** (+6 €/an) : sans NAT ni rebond, mais un SSH de plus exposé.
- **IPv6 publique seule** (gratuite) : ghcr.io et les runners GitHub n'ont pas
  d'IPv6, le NAT et le rebond resteraient (à confirmer).

## Conséquences

- Risque accepté : **Pangolin est le point unique** de la sortie de flip
  (apt, images, borg vers la Storage Box, Beszel et journaux, appels sortants
  des applis) et de son administration SSH ; une panne ou une reconstruction
  de Pangolin coupe aussi flip, publié ou non.
- Atténuations : `nat-client-watchdog` (rôle `nat_client`) remet route et DNS ;
  console Hetzner hors réseau ; runbooks [flip-injoignable.md](../runbooks/flip-injoignable.md),
  [pangolin-injoignable.md](../runbooks/pangolin-injoignable.md), [reconstruction-pangolin.md](../runbooks/reconstruction-pangolin.md).
- Aucune surface d'attaque directe sur flip ; rien à payer.

## Liens

`tofu/pangolin/nat.tf`, `flip.tf` ; `docs/architecture.md` ; [0002](0002-pangolin-seule-entree-publique.md).
