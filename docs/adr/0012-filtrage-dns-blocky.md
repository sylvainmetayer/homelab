# 0012. Filtrage DNS du réseau local : Blocky

- **Statut** : proposée (mise en œuvre par la PR du rôle `blocky`, acceptée une fois déployée)
- **Date** : 2026-10-28

## Contexte

Le réseau local n'a aucun filtrage DNS (publicités, traqueurs ; confirmé par
Sylvain le 2026-10-28, ni NextDNS ni autre). Une piste « AdGuard Like » a été
ouverte puis fermée (« completed ») en janvier 2026, sans déploiement (#29,
seule mention : NextDNS). Tout le reste du homelab est déclaré dans le
dépôt et déployé par Ansible ; un DNS réglé dans une UI y ferait exception.

## Décision

**Blocky**, parce que sa configuration est un fichier YAML : un rôle Ansible
le template, Molecule le valide, une PR le relit, comme le reste du dépôt.
Deux instances, que le DHCP de la Bbox annonce toutes les deux : le Pi
(conteneur) et le LXC newt (binaire, pas de Docker). Listes HaGeZi Pro et
TIF medium ; amont en DoT chez Quad9 et Mullvad. Bascule du DHCP faite à la
main dans la Bbox ([runbook](../runbooks/dns-blocky.md)).

## Alternatives écartées

- **AdGuard Home** et **Technitium DNS** : configurés surtout par leur UI ;
  leur état vit dans leur propre base ou fichier réécrit par l'appli, pas
  dans le dépôt.
- **NextDNS** (#29) : service tiers, hors de l'infrastructure as code
  (jamais mis en place).

## Conséquences

- Pas d'UI d'administration : un domaine à débloquer passe par une PR.
- Le DNS de la maison dépend de Blocky : deux hôtes, une panne de l'un ne
  coupe rien. Le DHCP se règle dans l'UI de la Bbox, hors du dépôt.
- Le LXC newt passe à 1 Gio (Blocky y prend jusqu'à 384 Mio avec ses listes).

## Liens

Issue #29 ; décision du 2026-10-28, hors PR.
