# homelab

Construction d'un cluster Talos dans mon homelab, étapes après étapes

## Installation manuelle

[Avancée commit par commit](https://github.com/sylvainmetayer/homelab/compare/ee54b2647d8cf13275b24dcf34b774b3697ed8c3...ad085471f3f17c4025057885fb43930150991a2c)

## Installation IaC

```
mise plugins add pulumni https://github.com/canha/asdf-pulumi.git
```

### Configuration State pulumi

```
cd pulumi
aws configure # définir access/secret key et `fr-par` en région
pulumi login 's3://pulumi-state?endpoint=https://s3.fr-par.scw.cloud&s3ForcePathStyle=true&region=fr-par'
```

On va récupérer la configuration de notre VMs créé précédement avec la [méthode du provider Proxmox](https://www.pulumi.com/registry/packages/proxmoxve/api-docs/vm/virtualmachine/#look-up)

Avant cela, il faut configurer les crédentials pour se connecter à Proxmox : https://www.pulumi.com/registry/packages/proxmoxve/installation-configuration/

On commence par créer un token dans Proxmox (TODO screen, ne pas cocher `provileges separation`, sinon, le token n'a aucun droit) puis on stocke les identifiants dans le state pulumi

```
pulumi config set --secret proxmox_api_token root@pam!pulumi=TOKEN
pulumi config set --secret proxmox_endpoint https://PROXMOX:8006
pulumi up
```

On est capable de récupérer des informations et de communiquer avec Promox, on va pouvoir créer des VMs !

Un fois la configuration ajoutée pour la VM, on peut constater qu'elle est créé dans Proxmox.

On configure donc avec le provider Pulumi notre machineConfig avec notre patch pour démarrer notre cluster Talos. On note ici qu'on a également rajouté un worker.

Côté Pulumi, il est nécessaire de wrapper les outputs dans des promesses pour récupérer les valeurs des IPs. TODO il y a surement une manière plus propre de faire cela => on peut faire de l'async/await

```shell
pulumi up
pulumi refresh 
pulumi up --diff
# FIXME pulumi refresh + import worker boostrap sinon, les boostrap sont en double ?

pulumi stack output talosConfig --show-secrets > talosconfig
mkdir -p ~/.kube
pulumi stack output kubeconfig --show-secrets > ~/.kube/config
# on peut omettre talosconfig avec la variable d'env TALOSCONFIG, voir mise.toml

talosctl config endpoint 192.168.1.201 
talosctl config nodes 192.168.1.201 192.168.1.211 192.168.1.212 192.168.1.213

talosctl health -n 192.168.1.201 
talosctl dmesg
talosctl dashboard 
```

Et on a maintenant un cluster Kubernetes fonctionnel ! 

```
$ kubectl get nodes
NAME       STATUS   ROLES           AGE     VERSION
host-003   Ready    control-plane   3m13s   v1.32.0
host-010   Ready    <none>          3m22s   v1.32.0
```

On va maintenant brancher flux pour automatiser l'installation des ressources du cluter en mode GitOps. Pour l'instant, on va suivre bêtement la [documentation](https://fluxcd.io/flux/get-started/) et on verra plus tard comme automatiser ça.

Pour les permissions du token, il faut à minima ça (en considérant que le dépôt existe déjà) 

![github-token-permission.png](images/github-token-permission.png)

```
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=homelab \
  --branch=main \
  --path=./clusters/homelab \
  --personal
```

On continue le tuto, et on commit dans notre dossier "clusters/homelab/default" l'application podinfo, qui va automatiquement être rajoutée au cluster. 

Prochaine étape : installer les composants de notre cluster via flux !

Avant cela, on fait un peu évoluer le code pulumi, pour ajouter des IPs statiques côté DHCP de ma box. Je n'ai pas trouvé comment faire autrement qu'en figeant les MACs côté Proxmox pour le moment, mais cela fonctionne. 

J'aurai pu me baser sur le hostname de la machine, mais je me retrouve constamment avec des hostname `Host-001`, ... qui ne sont pas constant.

J'en profite également pour partir sur 3 machines pour les workers, et ajouter une [VIP](https://www.talos.dev/v1.9/talos-guides/network/vip/) pour permettre d'avoir un seul point d'entrée sur l'API Kubernetes (même si ce n'est pas très utile avec un seul CP, on verra plus tard quand on en ajoute d'autres).

On va maintenant voir pour installer fluxCD depuis pulumi, afin d'avoir le bootstrap des configuration de notre cluster. Pour cela, il faut commencer par générer une clé SSH et la définir dans les paramètres du dépôt Github. Il nous faut donc un token Github avec les droits `Read code` et `Read/Write Administration`, uniquement sur notre dépôt que l'on défini en tant que secret avec la commande `pulumi config set github:token GITHUB_PAT --secret`

En suivant l'exemple disponible [ici](https://github.com/oun/pulumi-flux/blob/main/examples/nodejs/flux-sync/index.ts), on voit que l'on peut créer une installation de Flux puis récupérer la synchronisation de notre dépôt. Je n'ai pas commit les fichiers comme dans l'exemple, car je préfère laisser renovate faire les mises à jour et que flux CD soit 100% en lecture seule (on y viendra plus tard).

```
pulumi up
# Attention, il faut potentiellement l'appliquer 2 fois, en cas d'erreur de CRD manquante
pulumi up
```

Il nous reste à modifier les sources dans notre dépôt Git pour déployer nos applications. En théorie, nous n'aurons plus à toucher au code pulumi, le reste sera côté YAML.