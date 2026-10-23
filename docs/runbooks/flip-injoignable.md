# flip injoignable

flip est un serveur Hetzner **sans IP publique** (10.0.1.10, réseau privé
10.0.0.0/16). Il dépend de Pangolin pour trois choses : être publié (son Newt,
site `flip`), sortir sur Internet (NAT) et recevoir SSH (rebond).

## Symptôme

- Flip Planning (prod `flip-planning.sylvain.cloud`, démo
  `demo-planning.sylvain.dev`) et Promptoramix DOWN, les autres applis UP.
- Ou : les applis répondent, mais flip ne télécharge plus rien (apt, images,
  borg vers la Storage Box) : c'est le NAT.
- Ou : `mise run ssh_flip` échoue.

Si toutes les applis du homelab tombent : [pangolin-injoignable.md](pangolin-injoignable.md).

## Diagnostic

1. SSH par rebond sur Pangolin :

   ```bash
   cd ansible
   mise run ssh_flip
   ```

   La tâche lit `ansible_host` (IP privée) et le ProxyCommand dans
   l'inventaire (`inventory/hetzner.py`) et vérifie les clés contre
   `ansible/known_hosts`. Si le rebond lui-même échoue, tester
   `ssh sylvain@pangolin.sylvain.cloud` : Pangolin doit autoriser le
   transfert (`security_ssh_allow_tcp_forwarding: local`,
   `host_vars/pangolin/variables.yaml`).

2. SSH impossible même par rebond : **console Hetzner** du serveur `flip`
   (elle ne passe pas par le réseau), connexion `sylvain`.

3. Sur flip, la sortie Internet :

   ```bash
   ip -4 route show default          # attendu : default via 10.0.0.1
   systemctl status nat-client-watchdog
   journalctl -u nat-client-watchdog -n 50 --no-pager
   cat /etc/resolv.conf
   curl -sSI https://deb.debian.org | head -1
   ```

   La passerelle 10.0.0.1 est celle du réseau Hetzner, qui renvoie vers
   Pangolin (`hcloud_network_route.nat`, `tofu/pangolin/nat.tf`) ; ce n'est
   pas l'IP de Pangolin.

4. Sur Pangolin, le côté passerelle :

   ```bash
   sudo systemctl status nat-gateway
   sudo iptables -t nat -S POSTROUTING | grep MASQUERADE
   sudo ufw status verbose | grep -i route
   sysctl net.ipv4.ip_forward
   ```

5. Sur flip, la publication :

   ```bash
   systemctl --user status dc@newt
   docker logs --tail 100 newt
   systemctl --user status dc@flip_planning dc@demo_planning dc@demo_planning_kc dc@promptoramix
   ```

   Newt de flip : identifiants lus dans le state `pangolin_config`
   (`flip_newt_id` / `flip_newt_secret`), pas dans SOPS.

## Réparation

- **Route ou DNS effacés** : le watchdog les remet en 30 s au plus ; sinon
  `sudo systemctl restart nat-client-watchdog`, ou rejouer le rôle :

  ```bash
  cd ansible
  ansible-playbook flip.yml --tags nat --check --diff
  ansible-playbook flip.yml --tags nat
  ```

- **MASQUERADE absent sur Pangolin** : `sudo systemctl restart nat-gateway`,
  ou `ansible-playbook pangolin.yaml --tags nat`.
- **Route Hetzner absente ou pointant vers une ancienne IP** (après une
  reconstruction de Pangolin) : `mise run plan` puis `mise run apply`
  (`tofu/pangolin`) recrée `hcloud_network_route.nat`.
- **Newt de flip en panne** : `systemctl --user restart dc@newt`, depuis une
  session `mise run ssh_flip`. Jamais depuis `flip.internal` : cette
  ressource passe par ce même Newt, la session tomberait avec lui.
- **Identifiants Newt invalides** (site recréé) : `tofu apply` de
  `tofu/pangolin_config`, puis `ansible-playbook flip.yml --tags newt`.
- **Une appli seule** : [appli-en-panne.md](appli-en-panne.md).

## Vérification

```bash
mise run ssh_flip
curl -sSI https://deb.debian.org | head -1
systemctl --user is-active dc@newt dc@flip_planning
```

Les moniteurs Uptime Kuma de Flip Planning et de la démo repassent UP.

## Prévention

- Une play Ansible sur flip passe toujours par l'IP privée et le rebond
  (inventaire local comme CI), jamais par `flip.internal`.
- `nat_client` est le premier rôle de `flip.yml` : sans lui, Docker et apt ne
  peuvent rien télécharger.
- flip est protégé par `prevent_destroy` (`tofu/pangolin/flip.tf`) : il
  porte les bases de prod et de démo.
