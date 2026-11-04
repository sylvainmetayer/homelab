# 0028. La clé SSH de la CI reste équivalente à root : risque accepté

- **Statut** : acceptée
- **Date** : 2026-11-04

## Contexte

`deploy-docker-app.yaml` se connecte en `sylvain`, qui a `sudo NOPASSWD:ALL` (`ansible/00-setup.yaml`) : sa clé SSH équivaut à root.
`00-setup.yaml` pose toutes les clés de `keys/`, celle de la CI comprise, sur les quatre hôtes déployés et sur newt-lxc, où la CI
ne va jamais ; ni sur le NAS ni sur l'hôte Proxmox, qu'il exclut. L'étude du 04/11/2026 (hors dépôt) a chiffré un compte `deploy` et ses variantes.

## Décision

On garde ce compte et cette clé, sans compte `deploy` ni durcissement de plus. Le risque est accepté. Ce qui existe reste :
environnement `production` limité à `main`, tunnel OLM vers la maison, `ci_key_audit` et `ssh_login_notify`.

## Alternatives écartées

- Sudo limité à des commandes : Ansible lance un `sh` puis Python sur stdin ; autoriser ce `sh` revient à tout autoriser.
- Compte `deploy` limité au groupe `docker` : `docker run -v /:/host` reste root.
- `command=` dans `authorized_keys` : casse Ansible, sauf à passer à un modèle où chaque hôte tire sa configuration
  (semaines de travail, clé age sur chaque hôte tant que SOPS n'est pas découpé).
- `from=` : le LAN et le rebond limitent déjà docker, pi et flip, et le runner n'a pas d'IP fixe pour Pangolin.
- Certificats courts signés via OIDC : un signataire à maintenir et l'audit à refaire, pour la seule clé qui fuite après le run.
- Sortir Pangolin du déploiement au merge (rebond vers flip seul) : le gain le plus net, écarté pour garder le déploiement automatique.
- Retirer la clé de newt-lxc, juger l'audit par hôte et par étape : utiles, non retenus pour l'instant.

## Conséquences

- Risque accepté : qui obtient la clé obtient root, sans autre condition sur Pangolin, joignable depuis Internet, et de là sur flip.
- Du code malveillant dans le job de déploiement (action, paquet, collection) a la clé, la clé age et le tunnel à la fois :
  aucune option sur le compte ne l'arrête.
- `ci_key_audit` signale après coup, ne juge pas ce qui se passe pendant un run, et qui prend root assez vite peut couper Vector avant l'envoi.
- `tls_private_key.ci_deploy` n'a ni échéance ni entrée dans `rotation-des-secrets.md` ; la marche à suivre tient dans `deploiement-ci-casse.md`.
- À revoir si la CI change de modèle, si le dépôt accepte des contributeurs, ou après tout usage anormal de la clé.

## Liens

[0024](0024-deploiement-au-merge.md), [0027](0027-connexions-ssh-cles-connues.md) ; `tofu/github/ssh_key.tf` ; [deploiement-ci-casse.md](../runbooks/deploiement-ci-casse.md).
