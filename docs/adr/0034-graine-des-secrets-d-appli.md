# 0034. Graine dédiée pour les secrets d'appli dérivés

- **Statut** : acceptée
- **Date** : 2026-11-11

## Contexte

26 secrets de 13 rôles ne sont pas des clés SOPS : chacun vaut
`sha256(backup_passphrase ~ étiquette)` (mots de passe de base, sessions, JWT,
clés de chiffrement de HealthLog et TREK, poivre de Homebox, secrets de
MediaManager et de nas_proxy). `backup_passphrase` est aussi la passphrase de
tous les dépôts Borg : elle est sur chaque hôte sauvegardé et dans
l'environnement GitHub `restore-test`. Root sur un seul hôte, ou une fuite de ce
job, permet de recalculer les secrets d'applis d'autres hôtes ; et une rotation
de la passphrase sur incident changerait d'un coup 13 applis, dont deux
rendraient leurs données illisibles (audit du 11/11, constat sc4).

## Décision

Une variable commune `app_secrets_seed` (`group_vars/all/variables.yml`) :
`{{ app_secrets_master | default(backup_passphrase) }}`. Chaque dérivation
lit cette variable, étiquette inchangée. La clé SOPS s'appelle
`app_secrets_master` : elle ne porte pas le nom de la variable, qu'elle
masquerait (précédence SOPS, `check_sops_shadowing.py`).

Mise en œuvre en trois temps (`docs/runbooks/rotation-des-secrets.md`) : la PR
(aucune valeur ne change), la création de la clé avec la valeur de
`backup_passphrase`, puis la rotation de `backup_passphrase` seule.

## Alternatives écartées

- **Figer chaque dérivé en clé SOPS** : 26 clés de plus à inventorier et à
  tourner, pour des secrets sans échéance ; seuls HealthLog et TREK coûtent
  cher à changer.
- **Changer la graine tout de suite** : casse 13 applis au déploiement (mots de
  passe de base à reposer, données chiffrées illisibles).
- **Ne rien faire, l'écrire** : garde le couplage Borg et secrets d'applis.

## Conséquences

- Tant que `app_secrets_master` manque ou égale `backup_passphrase`, la
  séparation est nominale : la fuite de l'une donne l'autre. Elle ne devient
  réelle qu'après une rotation de `backup_passphrase` qui laisse
  `app_secrets_master` en place.
- `restore-test` ne reçoit que `backup_passphrase` ; `restore_test.py` ne dérive
  rien. La graine, elle, est lue par chaque playbook (un seul fichier SOPS) :
  elle reste sur tous les hôtes. Une séparation par hôte demanderait un second
  fichier.
- La clé SOPS a son entrée dans `secrets-rotation.yaml` (sans échéance).
- Tourner `app_secrets_master` coûte autant qu'avant (liste complète des dérivés
  et de leurs effets dans le runbook de rotation).

## Liens

- `ansible/group_vars/all/variables.yml`, `docs/runbooks/rotation-des-secrets.md`
- [0009](0009-sops-age-deux-fichiers.md) (clés nommées contre le masquage)
