# Restent faits main dans Uptime Kuma (relevé du 28/10/2026, #525) :
#   - page `onepoint` (publiée) : les moniteurs professionnels, faits main par
#     décision (external_monitors.tf), qu'une page déclarée ici devrait
#     référencer par identifiant brut ;
#   - clés d'API `test` / `testé` : le provider ne les gère pas et l'API ne
#     les liste pas, à vérifier et supprimer dans l'UI.
# La page `default` (« Services » : un groupe VPS vide et ActualBudget) et la
# maintenance 1 « Reset betisier.sylvain.dev » (liée à aucun moniteur, elle ne
# suspendait rien) sont supprimées à la main : rien ne les remplace. Le reset
# quotidien du bêtisier a son moniteur push (website_betisier.tf), la
# notification Telegram est déclarée dans notifications.tf.
#
# Page de statut publique du site personnel. Elle sert surtout aux badges du
# README du dépôt site : Uptime Kuma ne sert /api/badge/<id>/… que pour les
# sondes présentes sur une page de statut publiée.
resource "uptimekuma_status_page" "site" {
  slug        = "sylvain-dev"
  title       = "sylvain.dev"
  description = "Disponibilité du site personnel www.sylvain.dev"
  published   = true

  show_powered_by         = false
  show_tags               = false
  show_certificate_expiry = true

  public_group_list = [
    {
      name = "Site"
      monitor_list = [
        { id = uptimekuma_monitor_http.blog.id },
        { id = uptimekuma_monitor_http.blog_apex.id },
      ]
    },
  ]
}

output "status_page_site_url" {
  description = "Page de statut publique de sylvain.dev"
  value       = "${local.uptimekuma_endpoint}/status/${uptimekuma_status_page.site.slug}"
  sensitive   = true
}

output "status_page_site_badges" {
  description = "URL des badges de la sonde Blog, pour le README du dépôt site"
  value = {
    status = "${local.uptimekuma_endpoint}/api/badge/${uptimekuma_monitor_http.blog.id}/status"
    uptime = "${local.uptimekuma_endpoint}/api/badge/${uptimekuma_monitor_http.blog.id}/uptime/720"
    ping   = "${local.uptimekuma_endpoint}/api/badge/${uptimekuma_monitor_http.blog.id}/ping/24"
  }
  sensitive = true
}

# Lu par docker.yml (homepage_uptimekuma_url) : le widget Uptime Kuma de
# Homepage lit cette page côté serveur (GET /api/status-page/<slug>, sans
# compte), l'URL ne va pas au navigateur.
output "homepage_uptimekuma_url" {
  description = "URL d'Uptime Kuma, pour le widget de Homepage"
  value       = local.uptimekuma_endpoint
  sensitive   = true
}
