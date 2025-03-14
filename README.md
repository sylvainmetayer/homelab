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

