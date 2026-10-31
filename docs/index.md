# Homelab

La documentation du dépôt [homelab](https://github.com/sylvainmetayer/homelab),
publiée depuis son dossier `docs/` à chaque merge sur `main`.

- **Un incident en cours** : [runbooks](runbooks/README.md), un fichier par
  panne (symptôme, diagnostic, réparation, vérification).
- **La carte** : [architecture](architecture.md), les
  [applications](apps.md) et leur hôte.
- **Le pourquoi des choix** : les [décisions d'architecture](adr/README.md).
- **Les règles du dépôt** : les conventions (Ansible, CI, secrets, tests...),
  dans le menu.

Ce site passe par Pangolin : quand Pangolin ou la VM docker sont tombés, il
tombe avec eux. Le même contenu se lit alors sur GitHub, dans le dossier
[`docs/`](https://github.com/sylvainmetayer/homelab/tree/main/docs), ou dans
un clone local.
