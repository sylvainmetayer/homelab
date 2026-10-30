# 0009. Secrets : SOPS + age, deux fichiers, clés nommées contre le masquage

- **Statut** : acceptée ; emplacement des fichiers remplacé par [0018](0018-secrets-depot-prive.md)
- **Date** : 2026-10-17 (règle de nommage et garde-fou)

## Contexte

Les secrets vivent chiffrés dans le dépôt. Depuis ansible-core 2.21,
`community.sops.load_vars` les range dans la couche `include_vars`, devant
les `vars:` du play et des entrées `roles:`. Les secrets de la prod du
planning portaient les noms des variables que la démo surchargeait : la
montée de version aurait donné à la démo publique les secrets de la prod.

## Décision

- **SOPS + age**, deux fichiers : `secrets.sops.yaml` à la racine
  (environnement OpenTofu/mise) et `ansible/secrets.sops.yaml` (playbooks).
  Destinataires dans `.sops.yaml` : `perso`, `pro`, `secours` pour les deux,
  `github-actions` (CI) pour celui d'Ansible seulement.
- **Une clé SOPS ne porte jamais le nom d'une variable** qu'un play ou un
  rôle définit : on préfixe par instance (`prod_planning_*`,
  `demo_planning_*`) et on la passe dans les `vars:` de l'entrée.
- `.github/scripts/check_sops_shadowing.py` (workflow Lint) échoue sur tout
  nom qui masquerait une variable.

## Alternatives écartées

- **Garder les noms du rôle en SOPS et compter sur la précédence** : vrai en
  2.20 (`vars:` gagnait), faux en 2.21 (vérifié dans #762).
- **Un seul fichier** : la clé age de la CI ouvrirait aussi les secrets
  OpenTofu (commentaire en tête de `.sops.yaml`).

## Conséquences

- Les noms de clés sont plus longs et propres à une instance.
- Perte d'une clé age : [runbooks/perte-cle-ou-poste.md](../runbooks/perte-cle-ou-poste.md).

## Liens

PR #762 (issue #712) ; `.sops.yaml`, `.sopsrc`, AGENTS.md (« Secrets »).
