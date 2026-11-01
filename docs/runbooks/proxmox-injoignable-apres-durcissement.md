# Proxmox injoignable après durcissement

Le rôle `pve_hardening` (`pve.yml`, tags `pve_ssh`, `pve_firewall`,
`pve_sdn`, `pve_apt`) coupe les mots de passe SSH de root et active le
pare-feu PVE de l'hôte (22 et 8006 depuis 192.168.1.0/24 seulement). Détail :
`ansible/roles/pve_hardening/README.md`.

## Symptôme

- `ssh root@192.168.1.26` refusé (`Permission denied (publickey)`) ou qui
  attend sans répondre ;
- l'interface web `https://pve.sylvain.cloud:8006` ne charge plus ;
- `tofu -chdir=tofu/proxmox plan` échoue (API ou SSH du provider) ;
- la carte Proxmox de Homepage est rouge, ou les applis tombent juste après
  l'activation du pare-feu.

## Diagnostic

Depuis le PC, sur le LAN :

```bash
ping -c1 192.168.1.26                       # ICMP permis depuis le LAN
nc -vz -w3 192.168.1.26 22; nc -vz -w3 192.168.1.26 8006
ssh -v -o PasswordAuthentication=no root@192.168.1.26 true
```

| Constat | Cause probable |
|---|---|
| `Permission denied (publickey)` | sshd durci, la clé présentée n'est pas dans `/etc/pve/priv/authorized_keys` (agent vide, autre poste) |
| connexion qui expire sur 22 et 8006 | pare-feu : source hors du LAN (client Pangolin mal routé, autre réseau), ou règles cassées |
| ping et 22 répondent, applis en panne | trafic des invités filtré depuis l'activation (`bridge-nf-call-iptables`, paquets `INVALID` jetés) |
| plus rien ne répond, ping compris | pas le durcissement : hôte éteint, réseau, `ifreload` raté après la suppression du SDN |

Si une session root est encore ouverte (session de secours), tout se répare
depuis elle : les connexions établies passent le pare-feu.

## Réparation

**Accès de secours**, dans l'ordre :

1. la session root restée ouverte pendant le run ;
2. le Shell de l'interface web (nœud `proxmox` → Shell) si 8006 répond : il
   ne passe pas par sshd ;
3. **la console physique** : écran et clavier sur la machine (pas d'IPMI),
   login `root` avec son mot de passe (KeePass) : `login` local, ni sshd ni
   pare-feu.

**Pare-feu** :

```bash
pve-firewall stop                 # retire toutes les règles tout de suite
# puis, pour que le redémarrage du service ne les remette pas :
sed -i 's/^enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw
pve-firewall start && pve-firewall status   # disabled/running
```

Pour les applis seulement (pare-feu de l'hôte à garder) : ajouter
`nf_conntrack_allow_invalid: 1` dans `/etc/pve/nodes/proxmox/host.fw`
(section `[OPTIONS]`), ou désactiver comme ci-dessus.

**sshd** :

```bash
rm /etc/ssh/sshd_config.d/10-hardening.conf
sshd -t && systemctl reload ssh
```

Puis remettre la clé manquante dans `/etc/pve/priv/authorized_keys` plutôt
que de garder les mots de passe ouverts.

**SDN** : la zone `homelab` n'était utilisée par aucun invité (le rôle le
vérifie avant de supprimer). Si `ifreload -a` a laissé `vmbr0` dans un état
bancal : `ifreload -a` à nouveau depuis la console, ou `systemctl restart
networking`. `/etc/network/interfaces` n'est pas touché, seulement
`/etc/network/interfaces.d/sdn`.

## Vérification

```bash
ssh -o PasswordAuthentication=no root@192.168.1.26 'pve-firewall status; sshd -T | grep -E "^(permitrootlogin|passwordauthentication|x11forwarding) "'
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.1.26:8006/   # 200
tofu -chdir=tofu/proxmox plan     # aucun changement, API et SSH joignables
```

Et une appli derrière Pangolin (le Newt du LXC et de la VM docker passe par
le pont des invités).

## Prévention

- Appliquer une partie à la fois, chacune avec son `--check --diff`, une
  session root ouverte à côté (README du rôle, « Applying »).
- Le rôle refuse d'écrire le pare-feu si le run ne vient pas du LAN, et de
  couper les mots de passe si root n'a aucune clé.
- Après une désactivation à la main, corriger la cause puis relancer
  `ansible-playbook pve.yml --tags pve_firewall` : sinon le prochain run
  complet réactive le pare-feu sans prévenir.
