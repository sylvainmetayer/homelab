# Pangolin injoignable

## Symptôme

- **Toutes** les applis publiques tombent en même temps, sur tous les hôtes.
- `https://pangolin.sylvain.cloud` ne répond pas, ou erreur de certificat.
- Les ressources privées (`docker-apps.internal`, `pi.internal`) et le
  déploiement CI (tunnel OLM) ne marchent plus non plus.
- flip perd aussi Internet : il sort par le NAT de Pangolin.

## Diagnostic

Hors de la maison, le LAN (VM docker, Pi, Proxmox, NAS) reste joignable par
l'accès de secours WireGuard : [acces-de-secours.md](acces-de-secours.md).

1. Depuis le poste : DNS et ports.

   ```bash
   dig +short pangolin.sylvain.cloud      # doit donner l'IP de tofu/pangolin (ansible/known_hosts)
   curl -sSI https://pangolin.sylvain.cloud | head -1
   ssh sylvain@pangolin.sylvain.cloud
   ```

2. SSH impossible : **console Hetzner** (Cloud Console → serveur `pangolin`
   → Console). Connexion `sylvain` avec son mot de passe
   (`host_user_password_hash`). Regarder si la VM tourne, si le disque est
   plein (`df -h`), si le réseau est monté (`ip -4 addr`). Si l'IP du poste
   est bannie par fail2ban :

   ```bash
   sudo fail2ban-client status sshd
   sudo fail2ban-client set sshd unbanip <ip>
   ```

3. La pile Pangolin (unité **système**, root, `/opt/pangolin`) :

   ```bash
   sudo systemctl status pangolin
   sudo journalctl -u pangolin -n 100 --no-pager
   cd /opt/pangolin && docker compose ps
   docker logs --tail 100 pangolin
   docker logs --tail 100 gerbil
   docker logs --tail 100 traefik
   ```

   Ordre de démarrage : `pangolin` doit être `healthy` avant que `gerbil` et
   `traefik` démarrent (`depends_on` dans `ansible/roles/pangolin/templates/compose.yaml`).
   Traefik vit dans l'espace réseau de gerbil (`network_mode:
   service:gerbil`) : c'est gerbil qui publie 80, 443, 51820/udp et
   21820/udp.

4. Certificats : Traefik les tient dans `/opt/pangolin/config/letsencrypt/acme.json`.

   ```bash
   echo | openssl s_client -connect pangolin.sylvain.cloud:443 -servername pangolin.sylvain.cloud 2>/dev/null | openssl x509 -noout -dates
   docker logs traefik 2>&1 | grep -i acme | tail -20
   ```

5. Pare-feu : ufw sur la VM (`sudo ufw status`, ports de
   `host_vars/pangolin/variables.yaml`) et pare-feu Hetzner
   (`hcloud_firewall.pangolin`, `tofu/pangolin/pangolin.tf`).

6. NAT de flip : `sudo systemctl status nat-gateway` et
   `sudo iptables -t nat -S POSTROUTING | grep MASQUERADE`.

## Réparation

- **Pile arrêtée ou bloquée** : `sudo systemctl restart pangolin`. L'unité
  fait `docker compose down` puis `up -d` : gerbil et traefik sont recréés
  ensemble, rien n'est perdu (tout l'état est en montages bind sous
  `/opt/pangolin/config`).
- **Config cassée par un déploiement** : redéployer depuis le dépôt.

  ```bash
  cd ansible
  ansible-playbook pangolin.yaml --tags pangolin --check --diff
  ansible-playbook pangolin.yaml --tags pangolin
  ```

- **Base SQLite corrompue, `/opt/pangolin` perdu** : restaurer depuis Borg
  ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md), section
  SQLite ; l'appli s'appelle `pangolin`).
- **VM perdue** : [reconstruction-pangolin.md](reconstruction-pangolin.md).
- **Certificat expiré** : le défi Let's Encrypt est un défi HTTP sur le port
  80 (`httpChallenge`, entrée `web`, `traefik_config.yml.j2`). Vérifier que
  le port 80 est joignable depuis Internet (ufw et pare-feu Hetzner) et que
  `acme.json` est accessible en écriture, puis `docker restart traefik`.
- **NAT perdu** : `sudo systemctl restart nat-gateway`.

## Vérification

```bash
cd /opt/pangolin && docker compose ps   # pangolin healthy, gerbil et traefik Up
curl -sSI https://pangolin.sylvain.cloud | head -1
```

Les moniteurs Uptime Kuma repassent UP ; les sites Newt apparaissent en
ligne dans le tableau de bord ; flip sort de nouveau sur Internet
(`mise run ssh_flip` puis `curl -sSI https://deb.debian.org | head -1`).

## Prévention

- `pangolin.service` ne renonce jamais (`StartLimitIntervalSec=0`) et ne
  télécharge que les images absentes (`--pull missing`).
- Une montée de Pangolin, Gerbil, Traefik ou Newt arrive groupée par Renovate
  (`pangolin-role-dependencies`) : lire les notes de version avant de merger,
  le merge déploie.
- Sauvegarde nuitière de `/opt/pangolin` vers Borg, moniteur push associé.
