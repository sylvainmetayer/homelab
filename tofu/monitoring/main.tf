# Création d'un moniteur Push pour Uptime Kuma
resource "uptimekuma_monitor_push" "rss" {
  name = "RSS"

  interval = 86400 # 24 heures (1 jour)

  # Nombre de tentatives avant de marquer comme down
  retry_interval = 60
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}
