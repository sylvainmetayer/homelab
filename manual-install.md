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
