# Un hôte a changé de clé d'hôte SSH

Ansible, la CI et les tâches `mise run ssh`, `ssh_pi`, `ssh_flip` et `ssh_newt` vérifient les
clés d'hôte contre `ansible/known_hosts` (versionné), avec
`StrictHostKeyChecking=yes`
(`ansible.cfg`, ProxyCommand de `inventory/hetzner.py`, `~/.ssh/config` de la
CI). Une clé qui change fait **échouer** la connexion, elle n'est jamais
acceptée d'office.

## Symptôme

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
```

ou `Host key verification failed`, en local comme dans le run
`deploy-docker-app.yaml`.

## Diagnostic

La question : **le changement est-il voulu ?** Oui si l'hôte vient d'être
reconstruit (nouvelle VM, réinstallation du Pi). Sinon, traiter comme une
possible attaque (homme du milieu, DNS détourné) : ne pas se connecter, ne
rien accepter.

Relever l'empreinte attendue **par un canal sûr**, jamais par `ssh-keyscan`
ni par une première connexion « pour voir » à travers le réseau : c'est
justement ce canal qui est en doute.

| Hôte | Canal sûr | Commande |
|---|---|---|
| `pangolin`, `flip` | console Hetzner (Cloud Console → serveur → Console) | `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` |
| `docker` | agent invité, depuis le shell du nœud Proxmox (interface web → nœud `proxmox` → Shell) | `qm guest exec 100 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` |
| `pi` | écran et clavier branchés sur le Pi | `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` |
| Storage Box | empreinte publiée par Hetzner (documentation Storage Box) | rien à lancer sur la machine |

Comparer avec l'empreinte affichée par le message d'erreur de ssh. Si elles
diffèrent : arrêter, l'hôte en face n'est pas le bon.

## Réparation

1. Récupérer la clé publique elle-même par le même canal :
   `cat /etc/ssh/ssh_host_ed25519_key.pub`.
2. Dans `ansible/known_hosts`, remplacer la ligne de l'hôte en gardant
   **tous ses noms** : par exemple
   `docker,docker-apps.internal,192.168.1.216 ssh-ed25519 AAAA…`,
   `pangolin,pangolin.sylvain.cloud,<IP publique> ssh-ed25519 AAAA…`,
   `flip,10.0.1.10 ssh-ed25519 AAAA…`. Mettre à jour aussi l'empreinte
   `SHA256:…` dans le commentaire en tête du fichier.
3. Si l'IP a changé (Pangolin reconstruit), changer l'IP dans la ligne.
4. Retirer l'ancienne entrée de son propre `~/.ssh/known_hosts` si on s'y
   connecte aussi hors Ansible : `ssh-keygen -R <nom>`.
5. PR et merge : la CI lit ce même fichier.

## Vérification

```bash
cd ansible
ssh-keygen -lf known_hosts | grep <hôte>   # même empreinte que celle relevée
mise run ssh_flip                          # ou mise run ssh, mise run ssh_pi
ansible <hôte> -m ping
```

Et le run suivant de `deploy-docker-app.yaml` passe l'étape de connexion.

## Prévention

- Une reconstruction d'hôte inclut toujours cette étape (voir
  [reconstruction-pangolin.md](reconstruction-pangolin.md)).
- Ne jamais désactiver `StrictHostKeyChecking` pour « débloquer » un run :
  c'est le seul contrôle qui distingue l'hôte d'un imposteur.
