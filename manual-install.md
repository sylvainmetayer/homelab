# Installation manuelle Talos

Pré-requis : VM Proxmox configurée avec ISO Talos

```bash
export TALOS_IP=192.168.1.187

talosctl gen secrets
talosctl gen config homelab-test https://$TALOS_IP:6443 --with-secrets ./secrets.yaml --install-disk /dev/sda --config-patch @talos-patch.yaml --force
talosctl get disks --insecure -e $TALOS_IP -n $TALOS_IP
```

```text
NODE   NAMESPACE   TYPE   ID      VERSION   SIZE     READ ONLY   TRANSPORT   ROTATIONAL   WWID   MODEL           SERIAL
       runtime     Disk   loop0   1         4.1 kB   true
       runtime     Disk   loop1   1         684 kB   true
       runtime     Disk   loop2   1         74 MB    true
       runtime     Disk   sda     1         34 GB    false       virtio      true                QEMU HARDDISK
       runtime     Disk   sr0     1         105 MB   false       ata                             QEMU DVD-ROM
```

On veut donc installer Talos sur le disque /dev/sda qui est la plus grande partition.

```bash
# On installe Talos
talosctl apply-config --insecure -n $TALOS_IP -e $TALOS_IP --file controlplane.yaml

# On démarre etcd, cela va prendre quelques minutes le temps de démarrer tous les composants
talosctl bootstrap -e $TALOS_IP --talosconfig ./talosconfig  --nodes $TALOS_IP

# On récupère notre kubeconfig
talosctl kubeconfig  -e $TALOS_IP --talosconfig ./talosconfig  --nodes $TALOS_IP
```

A ce stade, on a un cluster Kubernetes utilisable.

## Test d'un pod basique

```bash
$ k apply -f 01-test-port-forward.yaml
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "nginx" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/nginx created
```

On peut maintenant configurer un port-forward : `kubectl port-forward deployments/nginx 8080:80`

Maintenant que l'on a vu que notre application fonctionne correctement, on peut tenter d'y accéder depuis l'extérieur, en installant un ingress controller. Je vais partir sur l'Ingress Controller NGINX, configuré avec un NodePort

```bash
helmfile init
helmfile apply
k apply -f 02-test-ingress.yaml
curl http://$TALOS_IP:32080/nginx
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

On accède à notre application depuis l'IP de notre node ! Il nous reste le certificat à gérer, ainsi que la configuration automatique des enregistrements DNS afin de pouvoir déployer notre application de manière plus ou moins automatisée.

Commençons par installer les outils nécessaires pour générer un certificat pour notre ingress. J'utilise la validation ACME DNS avec mon domaine OVH, qui va déclarer un enregistrement DNS pour valider que l'on est bien le propriétaire du domaine. Ainsi, pas la peine d'ouvrir le port 80 pour valider le domaine via HTTP. On installe donc cert-manager et le plugin OVH associé. Pour cela, il faudra bien évidemment avoir des identifants pour interagir avec OVH, on se génère donc une clé d'API [ici](https://www.ovh.com/auth/api/createToken?GET=/*&POST=/*&PUT=/*&DELETE=/*)

```bash
cp values/cert-manager-ovh.EXAMPLE.yaml values/cert-manager-ovh.yaml
# on mets à jour avec son domaine et ses clés d'API
vim values/cert-manager-ovh.yaml

# J'ai essayé de jouer avec les secrets helmfile et une intégration sops, mais n'arrive pas à merger les values et les secrets correctement, on va donc rester sur un fichier en mode gitignore pour l'instant.

# Il faut installer en premier la release cert-manager qui installe les CRDs utilisés par le deuxième chart.
helmfile apply -l module=cert-manager

helmfile apply

```

Il nous reste à modifier notre ingress pour ajouter une annotation et la partie TLS, et notre certificat sera ensuite automatiquement généré par cert-manager.

```bash
k apply -f 02-test-ingress.yaml
```

Quand on regarde les logs de cert-manager, on voit que l'enregistrement est créé et qu'après quelques minutes, notre certificat est disponible !

```
I0303 21:51:07.162136       1 dns.go:90] "presenting DNS01 challenge for domain" logger="cert-manager.controller.Present" resource_name="nginx-sylvain-cloud-tls-1-772529587-1208554888" resource_namespace="default" resource_kind="Challenge" resource_version="v1" dnsName="nginx.sylvain.cloud" type="DNS-01" resource_name="nginx-sylvain-cloud-tls-1-772529587-1208554888" resource_namespace="default" resource_kind="Challenge" resource_version="v1" domain="nginx.sylvain.cloud"
E0303 21:51:07.633314       1 sync.go:208] "propagation check failed" err="DNS record for \"nginx.sylvain.cloud\" not yet propagated" logger="cert-manager.controller" resource_name="nginx-sylvain-cloud-tls-1-772529587-1208554888" resource_namespace="default" resource_kind="Challenge" resource_version="v1" dnsName="nginx.sylvain.cloud" type="DNS-01"
E0303 21:51:07.662802       1 sync.go:208] "propagation check failed" err="DNS record for \"nginx.sylvain.cloud\" not yet propagated" logger="cert-manager.controller" resource_name="nginx-sylvain-cloud-tls-1-772529587-1208554888" resource_namespace="default" resource_kind="Challenge" resource_version="v1" dnsName="nginx.sylvain.cloud" type="DNS-01"
I0303 21:52:20.573016       1 acme.go:236] "certificate issued" logger="cert-manager.controller.sign" resource_name="nginx-sylvain-cloud-tls-1" resource_namespace="default"
```

```
Name:         nginx-sylvain-cloud-tls
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2025-03-03T21:51:05Z
  Generation:          1
  Owner References:
    API Version:           networking.k8s.io/v1
    Block Owner Deletion:  true
    Controller:            true
    Kind:                  Ingress
    Name:                  nginx
    UID:                   4f18dc90-d006-4e69-932e-c960a0b2f37a
  Resource Version:        5784
  UID:                     9735a549-b349-4944-9996-933b4381a10b
Spec:
  Dns Names:
    nginx.sylvain.cloud
  Issuer Ref:
    Group:      cert-manager.io
    Kind:       ClusterIssuer
    Name:       ovh
  Secret Name:  nginx-sylvain-cloud-tls
  Usages:
    digital signature
    key encipherment
Status:
  Conditions:
    Last Transition Time:  2025-03-03T21:52:20Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2025-06-01T20:53:48Z
  Not Before:              2025-03-03T20:53:49Z
  Renewal Time:            2025-05-02T20:53:48Z
  Revision:                1
Events:
  Type    Reason     Age    From                                       Message
  ----    ------     ----   ----                                       -------
  Normal  Issuing    2m53s  cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  2m53s  cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "nginx-sylvain-cloud-tls-twvz7"
  Normal  Requested  2m53s  cert-manager-certificates-request-manager  Created new CertificateRequest resource "nginx-sylvain-cloud-tls-1"
  Normal  Issuing    98s    cert-manager-certificates-issuing          The certificate has been successfully issued
```

Il nous reste maintenant à trouver comment définir automatiquement l'enregistrement DNS pour accéder à notre service. Pour cela, nous allons installer ExternalDNS, qui va automatiquement créer les enregistrements DNS. OVH n'étant pas un provider compatible via le [chart helm](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns#providers), on va suivre la [documentation disponible](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/ovh.md)

```bash
cp 03-external-dns.EXAMPLE.yaml 03-external-dns.yaml
# on mets à jour avec son domaine et ses clés d'API
vim 03-external-dns.yaml
k apply -f 03-external-dns.yaml
```

Une fois installé, on peut voir qu'ExternalDNS va directement appliquer les changements de notre domaine par rapport à ce qui été définis dans nos ingress et nos services.

```
time="2025-03-03T22:19:25Z" level=info msg="OVH: 1 zones found"
time="2025-03-03T22:19:26Z" level=info msg="OVH: 9 changes will be done"
time="2025-03-03T22:19:26Z" level=info msg="OVH: 1 zones will be refreshed"
time="2025-03-03T22:20:25Z" level=info msg="OVH: 1 zones found"
time="2025-03-03T22:20:25Z" level=info msg="OVH: 14 endpoints have been found"
time="2025-03-03T22:20:25Z" level=info msg="All records are already up to date"
```

Cependant, l'IP associée à l'enregistrement DNS est l'IP du service, et non mon IP externe.

```
Name:             nginx
Labels:           <none>
Namespace:        default
Address:          10.100.60.11
```

![External DNS](image.png)

Je n'ai pour l'instant pas trouvé d'autre solution que de définir manuellement l'IP cible souhaitée en tant qu'annotation dans mon ingress afin que la bonne IP soit affectée.

Reste maintenant à configurer le routeur de la box pour rediriger le port 443 vers le port 32443 de notre $TALOS_IP, et nous devrions pouvoir accéder à notre application via internet !
