# 0012. Filtrage DNS du réseau local : Blocky

- **Statut** : proposée (aucune PR à ce jour)
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
Hôte, listes de blocage et bascule du DHCP : à décider dans la PR.

## Alternatives écartées

- **AdGuard Home** et **Technitium DNS** : configurés surtout par leur UI ;
  leur état vit dans leur propre base ou fichier réécrit par l'appli, pas
  dans le dépôt.
- **NextDNS** (#29) : service tiers, hors de l'infrastructure as code
  (jamais mis en place).

## Conséquences

- Pas d'UI d'administration : un domaine à débloquer passe par une PR.
- Le DNS de toute la maison dépend de l'hôte de Blocky : prévoir un second
  résolveur dans le DHCP, ou accepter la panne.

## Liens

Issue #29 ; décision du 2026-10-28, hors PR.
