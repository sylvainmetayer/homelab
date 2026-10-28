# Restent faits main dans Uptime Kuma (relevé du 28/10/2026, #525), en
# attendant une décision de Sylvain :
#   - page `default` (« Services », publiée) : un groupe VPS vide et ActualBudget
#     (uptimekuma_monitor_http.actualbudget), rien d'autre ;
#   - page `onepoint` (publiée) : les moniteurs professionnels, faits main par
#     décision (external_monitors.tf), qu'une page déclarée ici devrait
#     référencer par identifiant brut ;
#   - maintenance 1 « Reset betisier.sylvain.dev » (récurrente, active) : liée
#     à aucun moniteur, seulement à la page `default`, elle ne suspend rien
#     (le reset quotidien pousse de lui-même vers betisier_reset_healthcheck_url,
#     clé SOPS d'ansible/secrets.sops.yaml) ;
#   - clés d'API `test` / `testé` : le provider ne les gère pas et l'API ne
#     les liste pas, à vérifier et supprimer dans l'UI.
# La notification « Supervision Telegram » est traitée dans notifications.tf.
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
