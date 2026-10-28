# Page de statut des sauvegardes, pour le widget Uptime Kuma de Homepage
# (rôle homepage) : Uptime Kuma n'a pas d'API de lecture, le widget compte les
# sondes en ligne et en panne d'une page de statut publiée, sans compte
# (GET /api/status-page/<slug>). Son slug est celui de
# homepage_uptimekuma_status_pages (ansible/roles/homepage/defaults/main.yml,
# test homepage_status_pages_match_the_role).
#
# Publiée, donc lisible par qui connaît l'URL d'Uptime Kuma (une clé SOPS,
# UPTIMEKUMA_ENDPOINT) : les noms des sondes et leur état, rien d'autre, ni
# jeton push ni lien vers les applications.
#
# Chaque sauvegarde (une par entrée de local.websites avec backup = true, sauf
# les applis en pause, dont la sonde est arrêtée et ne compterait que comme
# « en attente », plus Pangolin et Jellyfin), et les deux contrôles qui en
# dépendent : le restore test et le remplissage de la Storage Box.
resource "uptimekuma_status_page" "backups" {
  slug        = "homelab-sauvegardes"
  title       = "Sauvegardes du homelab"
  description = "Sauvegardes borgmatic de la nuit et contrôles des dépôts"
  published   = true

  show_powered_by         = false
  show_tags               = false
  show_certificate_expiry = false

  public_group_list = [
    {
      name = "Sauvegardes"
      monitor_list = concat(
        [
          for monitor in values(uptimekuma_monitor_push.backup) : { id = monitor.id } if monitor.active
        ],
        [
          { id = uptimekuma_monitor_push.backup_pangolin.id },
          { id = uptimekuma_monitor_push.backup_jellyfin.id },
        ],
      )
    },
    {
      name = "Contrôles"
      monitor_list = [
        { id = uptimekuma_monitor_push.restore_test.id },
        { id = uptimekuma_monitor_push.storage_box_quota.id },
      ]
    },
  ]
}

# Lu par docker.yml (homepage_uptimekuma_url) : les widgets Uptime Kuma de
# Homepage interrogent l'instance côté serveur, l'URL ne va pas au navigateur.
output "homepage_uptimekuma_url" {
  description = "URL d'Uptime Kuma, pour les widgets de Homepage"
  value       = local.uptimekuma_endpoint
  sensitive   = true
}
