# Migration Proxmox/Ansible - LXC par brique applicative

Ce document résume:
1. ce qui a déjà été implémenté dans le repo,
2. ce qu'il reste à faire pour finaliser la migration en environnement réel.

## Objectif

Passer d'un modèle monolithique (VM `docker` + LXC `newt`) à un modèle:

- **1 LXC par rôle applicatif Ansible**,
- provisionné via OpenTofu (`tofu/proxmox`),
- puis configuré via Ansible en SSH avec des clés injectées depuis `keys/*.pub`.

## Ce qui a été fait

## 1) OpenTofu `tofu/proxmox`

- Ajout d'un modèle déclaratif applicatif:
  - variable `lxc_apps` dans `tofu/proxmox/variables.tf`.
- Provisionning des LXCs applicatifs via `for_each`:
  - nouveau fichier `tofu/proxmox/proxmox_apps_lxc.tf`.
- Injection des clés publiques SSH:
  - toutes les clés `keys/*.pub` sont injectées dans `initialization.user_account.keys`.
- Tagging standardisé:
  - tags communs + `role:<nom_role>` par conteneur.
- Nouveaux outputs:
  - `app_lxc_ips`,
  - `app_lxc_passwords` (sensitive),
  - dans `tofu/proxmox/outputs.tf`.
- Définition initiale des LXCs applicatifs dans `tofu/proxmox/terraform.tfvars`:
  - `echo`, `rss`, `betisier`, `monica_v4`, `wiki`, `nextcloud`, `semaphore`, `meerkat_crm`.

## 2) Inventaire dynamique Ansible

- Mise à jour de `ansible/inventory/proxmox.py`:
  - découverte des ressources Proxmox depuis `tofu show -json`,
  - extraction IP plus robuste (VM + LXC),
  - création de groupes par rôle à partir des tags `role:<x>`,
  - ajout d'un groupe agrégé `proxmox_apps`.

## 3) Refactor des playbooks Ansible

- Refonte de `ansible/docker.yml` en mode multi-plays:
  - play runtime commun sur `hosts: proxmox_apps`:
    - `geerlingguy.docker`,
    - `docker_service`,
    - `borgmatic`.
  - puis un play par rôle applicatif:
    - `echo`, `rss`, `betisier`, `monica_v4`, `wiki`, `nextcloud`, `semaphore`, `meerkat_crm`.

## 4) Variables Ansible

- Correction SSH globale:
  - `ansible/group_vars/all/variables.yml`
  - `ansible_ssh_private_key_file` passe de `~/.ssh/keepassxc.pub` à `~/.ssh/keepassxc` (clé privée).
- Migration des variables applicatives:
  - nettoyage de `ansible/host_vars/docker/variables.yaml`,
  - ajout de variables par rôle dans:
    - `ansible/group_vars/rss/variables.yml`
    - `ansible/group_vars/betisier/variables.yml`
    - `ansible/group_vars/monica_v4/variables.yml`
    - `ansible/group_vars/wiki/variables.yml`
    - `ansible/group_vars/nextcloud/variables.yml`
    - `ansible/group_vars/semaphore/variables.yml`
    - `ansible/group_vars/meerkat_crm/variables.yml`

## Ce qu'il te reste à faire (opérationnel)

## 1) Appliquer l'infra Proxmox

Depuis la racine:

```bash
mise run init-proxmox
mise run plan-proxmox
mise run apply-proxmox
```

Points de contrôle:
- vérifier que chaque LXC applicatif est créé, démarré, et joignable en SSH;
- vérifier IP/hostname/vm_id selon `terraform.tfvars`.

## 2) Vérifier l'inventaire dynamique

```bash
cd ansible
./inventory/proxmox.py --list
ansible-inventory -i inventory --graph
```

Tu dois voir:
- groupe `proxmox_apps`,
- groupes applicatifs (`echo`, `rss`, `betisier`, etc.),
- hosts mappés avec la bonne IP.

## 3) Préparer les secrets et prérequis

- Exporter la clé SOPS Age avant exécution Ansible.
- Vérifier les secrets requis dans `secrets.sops.yaml` pour chaque rôle.
- Vérifier la présence de la clé privée locale `~/.ssh/keepassxc`.

## 4) Exécuter la config Ansible

Ordre recommandé:

```bash
cd ansible
ansible-playbook -i inventory 00-setup.yaml
ansible-playbook -i inventory docker.yml
```

Puis exécution par rôle (optionnel) via `--limit` pour itérer service par service.

## 5) Migrer les données applicatives (service par service)

Pour chaque service:
1. arrêter/figer les écritures sur l'ancien host,
2. synchroniser volumes/données vers le nouveau LXC,
3. relancer + valider la santé applicative,
4. basculer DNS / routage,
5. monitorer avant de passer au service suivant.

## 6) Décommissionner l'ancien modèle

Quand tous les services sont migrés et stables:
- retirer les rôles applicatifs résiduels liés à l'ancien host monolithique,
- supprimer la VM `docker` uniquement en fin de migration.

## Limitations connues / remarques

- L'inventaire dynamique reflète l'état **déjà appliqué** dans OpenTofu; avant `apply`, les nouveaux groupes/hosts ne seront pas visibles.
- Le lint global du repo contient des erreurs historiques hors scope de cette migration; elles n'ont pas été corrigées ici.
- `newt` reste en LXC dédié hors périmètre "rôles applicatifs", conformément à la décision prise.
