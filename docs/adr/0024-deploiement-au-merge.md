# 0024. Le merge sur `main` déploie : quatre playbooks en CI, Tofu et le reste à la main

- **Statut** : acceptée (fenêtre de calme : [0029](0029-fenetre-de-calme-du-deploiement.md))
- **Date** : 2026-08-05 (docker, écrit le 2026-08-02 ; pi, pangolin), 2026-09-30 (flip)

## Contexte

La maison n'a aucun port entrant : un runner GitHub l'atteint par un tunnel OLM,
que `ping.yaml` utilisait déjà. Motif non écrit (`a25a5447` dit le comment seulement) : à confirmer.

## Décision

- **Un push sur `main` touchant Ansible ou les docs lance `deploy-docker-app`** :
  docker et pi par le tunnel OLM, pangolin en direct, flip par rebond, avec les tags que
  `resolve_docker_tags.py` tire des fichiers changés. Environnement `production` : `main` seule, sans relecteur.
- **Les autres playbooks à la main** : `nas.yml`, `pve.yml` (aucune clé du NAS ni de
  l'hôte Proxmox dans les secrets GitHub), `lxc.yml` (le LXC porte le chemin de la CI
  vers le LAN), `00-setup.yaml` (tous les hôtes d'un coup).
- **Tofu à la main**, par Sylvain. Un bump de `secrets/` ne déploie rien.

## Alternatives écartées

- **Tout le playbook à chaque merge** : gardé pour ce qui ne se dérive pas
  (`pre_tasks`, `host_vars`, fichiers partagés ; ces derniers « heavy » d'après `ci.md`).
- **flip par `flip.internal`** : servi par le Newt de flip, qu'un déploiement peut
  redémarrer en plein play. Rebond SSH par Pangolin à la place.
- Écarté le 2026-11-04 : **Tofu en CI** (#704 fermée : jetons, passphrase, API Pangolin ; tout reste en local).

## Conséquences

- Merger, c'est livrer ; chaque PR dit ce que son merge déploie, et l'automerge de
  Renovate ([0008](0008-renovate-hebdomadaire.md)) déploie sans personne.
- La clé age de la CI déchiffre tout `ansible.sops.yaml` ([0009](0009-sops-age-deux-fichiers.md)).
- Un `tofu apply` doit parfois précéder le merge (URL push vide sinon, #1044).
- Runs en série (OLM refuse une seconde connexion) ; `nas`, `pve` et `lxc`
  restent en retard sur `main` jusqu'au passage à la main.

## Liens

PR #395, #639 ; [ci.md](../conventions/ci.md), [runbooks/deploiement-ci-casse.md](../runbooks/deploiement-ci-casse.md).
