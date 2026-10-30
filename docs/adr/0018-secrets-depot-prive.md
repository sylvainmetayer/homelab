# 0018. Secrets dans un dépôt privé, monté en sous-module

- **Statut** : acceptée
- **Date** : 2026-10-30

## Contexte

Dépôt public : les fichiers SOPS publiaient le chiffré de chaque secret,
`secrets-rotation.yaml` leur inventaire. Age post-quantique (#1021) ou pas.

## Décision

- Dépôt **privé** `homelab-secrets` (`tofu/github`), **sous-module à
  `secrets/`** : `secrets.sops.yaml` (OpenTofu, mise), `ansible.sops.yaml`
  (playbooks), `secrets-rotation.yaml`. `.sops.yaml` (clés publiques) et les
  contrôles restent ici.
- La CI le clone au commit épinglé (`.github/actions/secrets-checkout`) avec
  une **clé de déploiement en lecture seule**, secret **du dépôt**
  `HOMELAB_SECRETS_SSH_KEY` (un environnement n'est lu que depuis main, le
  Lint des PR en a besoin) : Lint, déploiement, échéances de rotation.
  Molecule et `tofu test` s'en passent.
- GitHub Free, pas de ruleset sur un privé : aucun collaborateur, pas d'Actions.

## Alternatives écartées

- **Tâche mise clonant dans un chemin ignoré** : rien d'épinglé, la CI et
  un poste liraient des versions différentes sans le voir.
- **Sous-module aux chemins actuels** : impossible, deux fichiers dans deux
  dossiers. **Jeton à grain fin** : fait main, expire.
- **Réécrire l'historique** : les anciens blobs restent ; rotations à part.

## Conséquences

- `git submodule update --init` sur chaque poste ; changer un secret = un
  commit dans `homelab-secrets`, puis le bump du sous-module ici.
- Une PR de fork échoue à l'« Ansible lint » (pas de secret).

## Liens

ADR 0009 ; `tofu/github/README.md` ; `docs/conventions/secrets.md`.
