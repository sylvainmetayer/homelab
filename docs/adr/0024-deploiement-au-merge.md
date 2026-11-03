# 0024. Le merge sur `main` déploie : Ansible en CI, Tofu et trois playbooks à la main

- **Statut** : acceptée (Tofu en CI ouvert : #704)
- **Date** : 2026-08-02 (docker), 2026-08-05 (pi, pangolin), 2026-09-30 (flip)

## Contexte

La maison et flip n'ont aucun port entrant : un runner GitHub les atteint par un
tunnel OLM, que `ping.yaml` utilisait déjà. Motif de l'automatisation non écrit
(`a25a5447` dit le comment seulement) : à confirmer.

## Décision

- **Un push sur `main` lance `deploy-docker-app`** par le tunnel OLM : docker, pi,
  pangolin et flip, avec les tags que `resolve_docker_tags.py` tire des fichiers
  changés. Environnement `production` : `main` seule, sans relecteur.
- **`nas.yml`, `pve.yml` et `lxc.yml` à la main** : ni le NAS ni l'hôte Proxmox
  n'ont de clé dans les secrets GitHub (raison du choix, et du LXC, non écrite).
- **Tofu à la main**, par Sylvain. Un bump de `secrets/` ne déploie rien.

## Alternatives écartées

- **Tout le playbook à chaque merge** : gardé pour ce qui ne se dérive pas
  (`pre_tasks`, `host_vars`, fichiers partagés), « lourd » d'après `ci.md`.
- **flip par `flip.internal`** : servi par le Newt de flip, qu'un déploiement peut
  redémarrer en plein play. Rebond SSH par Pangolin à la place.
- **Diff depuis le `before` du push** : un run en attente annulé perdrait ses
  fichiers. Base : la tête du dernier run réussi.

En attente, pas écarté : **Tofu en CI** (#704 : jetons, passphrase, API Pangolin).

## Conséquences

- Merger, c'est livrer ; chaque PR dit ce que son merge déploie, et l'automerge de
  Renovate ([0008](0008-renovate-hebdomadaire.md)) déploie sans personne.
- La clé age de la CI déchiffre tout `ansible.sops.yaml` ([0018](0018-secrets-depot-prive.md)).
- Un `tofu apply` doit parfois précéder le merge (URL push vide sinon, #1044).
- Runs en série (OLM refuse une seconde connexion) ; `nas`, `pve` et `lxc`
  restent en retard sur `main` jusqu'au passage à la main.

## Liens

PR #395, #639 ; [ci.md](../conventions/ci.md), [runbooks/deploiement-ci-casse.md](../runbooks/deploiement-ci-casse.md).
