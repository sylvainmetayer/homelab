# Configuration de la VM
vm_name     = "pangolin"
server_type = "CX23"
image       = "debian-13"
location    = "nbg1"

ssh_key_name    = "keepassxc"
ssh_allowed_ips = ["0.0.0.0/0", "::/0"]

labels = {
  managed_by = "opentofu"
}

# Configuration cloud-init avec hardening pour Zero Trust
user_data = <<-EOF
#cloud-config
users:
  - name: sylvain
    groups: sudo, docker
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    passwd: $6$rounds=4096$saltsaltsal$YhpKJqedPMzHJ6k/FKKUo4woZNrEV3ZjVgFXNdgYMFGN1kLq.DHrJKx//yGj5OKj4epDHqQ6rCM1SEF4W.xE0/
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRXHnjOoW9mZpkOsJ0dgVzhTl/cBEvYKRchhKvwT5aB keepassxc-ssh-key

ssh_pwauth: false

write_files:
  # Configuration SSH durcie
  - path: /etc/ssh/sshd_config.d/99-custom.conf
    content: |
      PasswordAuthentication no
      PubkeyAuthentication yes
      ChallengeResponseAuthentication no
      PermitRootLogin no
      MaxAuthTries 3
      MaxSessions 2
      ClientAliveInterval 600
      ClientAliveCountMax 2
      X11Forwarding no
      AllowTcpForwarding no
      PermitEmptyPasswords no
      Protocol 2
      UsePAM yes
      LogLevel VERBOSE
    permissions: '0644'

  - path: /etc/sysctl.d/99-hardening.conf
    content: |
      # Désactivation de l'IPv6 si non utilisé
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1

      # Limites de fichiers
      fs.file-max = 65535
      fs.suid_dumpable = 0
    permissions: '0644'

  # Configuration fail2ban pour SSH
  - path: /etc/fail2ban/jail.local
    content: |
      [DEFAULT]
      bantime = 3600
      findtime = 600
      maxretry = 3
      destemail = root@localhost

      [sshd]
      enabled = true
      port = 22
      logpath = /var/log/auth.log
      maxretry = 3
      bantime = 7200
    permissions: '0644'

  # Configuration des mises à jour automatiques de sécurité
  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    content: |
      Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
      };
      Unattended-Upgrade::AutoFixInterruptedDpkg "true";
      Unattended-Upgrade::MinimalSteps "true";
      Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::Automatic-Reboot "false";
      Unattended-Upgrade::Automatic-Reboot-Time "03:00";
    permissions: '0644'

package_update: true
package_upgrade: true
packages:
  - docker.io
  - fail2ban
  - ufw
  - unattended-upgrades
  - apt-listchanges
  - auditd
  - logwatch
  - rkhunter

runcmd:
  # Configuration du firewall UFW
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable

  # Configuration fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban

  # Configuration Docker
  - systemctl enable docker
  - systemctl start docker

  # Configuration SSH
  - systemctl restart sshd

  # Application des paramètres sysctl
  - sysctl -p /etc/sysctl.d/99-hardening.conf

  # Configuration auditd
  - systemctl enable auditd
  - systemctl start auditd

  # Configuration des mises à jour automatiques
  - dpkg-reconfigure -plow unattended-upgrades

  # Nettoyage
  - apt-get autoremove -y
  - apt-get autoclean -y

  # Log de fin de configuration
  - echo "Hardening configuration completed at $(date)" >> /var/log/cloud-init-hardening.log

# Désactivation des services inutiles
disable_root: true
EOF
