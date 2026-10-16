# ---------------------------------------------------------------------------
# Alerte à chaque connexion SSH (issue #451).
#
# Un moniteur push par hôte. Le rôle Ansible ssh_login_notify (appliqué par
# 00-setup.yaml) pose un hook pam_exec dans /etc/pam.d/sshd qui pousse
# `status=up&msg=<utilisateur, IP, clé>` à chaque ouverture de session.
#
# Les moniteurs sont inversés (upside_down) : un push les fait passer DOWN, ce
# qui envoie la notification avec le message ; sans push pendant `interval`
# secondes ils repassent UP (second message, de retour au calme). Des
# connexions sur le même hôte à moins de 60 s d'écart sont donc fusionnées
# dans une seule alerte.
#
# Les clés de local.ssh_login_hosts sont des inventory_hostname : 00-setup.yaml
# lit `terraform_outputs.uptime_ssh_login_urls.value[inventory_hostname]`, un
# hôte absent d'ici n'a pas d'URL et le rôle ne pose rien (avertissement).
# ---------------------------------------------------------------------------

locals {
  ssh_login_hosts = toset(["docker", "flip", "pangolin", "pi"])
}

resource "uptimekuma_monitor_group" "ssh_logins" {
  name = "Connexions SSH"

  # Tous les attributs optional+computed sont épinglés (piège du provider,
  # cf. notifications.tf) ; valeurs par défaut d'un dossier Uptime Kuma.
  active          = true
  interval        = 60
  retry_interval  = 60
  max_retries     = 0
  resend_interval = 0
  upside_down     = false

  tags = [local.tofu_tag]
}

resource "uptimekuma_monitor_push" "ssh_login" {
  for_each = local.ssh_login_hosts

  name        = "SSH ${each.key}"
  description = "Une alerte par connexion SSH sur ${each.key} (rôle Ansible ssh_login_notify)."
  parent      = uptimekuma_monitor_group.ssh_logins.id

  # Inversé : un push = DOWN = notification ; 60 s sans push = retour UP.
  upside_down     = true
  interval        = 60
  retry_interval  = 60
  max_retries     = 0 # la première connexion alerte, sans période PENDING
  resend_interval = 0
  active          = true

  notification_ids = [local.telegram_notification_id]
  tags             = [local.tofu_tag]
}

output "uptime_ssh_login_urls" {
  description = "SSH - URL push de chaque hôte (clé = inventory_hostname), lue par 00-setup.yaml"
  value = {
    for host, monitor in uptimekuma_monitor_push.ssh_login :
    host => "${local.uptimekuma_endpoint}/api/push/${monitor.push_token}"
  }
  sensitive = true
}
