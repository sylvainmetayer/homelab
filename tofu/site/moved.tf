# Ressources passées dans le module commun tofu/modules/pages_site (2026-10-29).
# À garder tant que l'état n'a pas été appliqué avec ces adresses.

moved {
  from = github_repository.site
  to   = module.pages.github_repository.this
}

moved {
  from = github_repository_vulnerability_alerts.site
  to   = module.pages.github_repository_vulnerability_alerts.this
}

moved {
  from = github_repository_dependabot_security_updates.site
  to   = module.pages.github_repository_dependabot_security_updates.this
}

moved {
  from = github_app_installation_repository.cloudflare
  to   = module.pages.github_app_installation_repository.cloudflare
}

moved {
  from = cloudflare_pages_project.site
  to   = module.pages.cloudflare_pages_project.env_vars[0]
}

moved {
  from = cloudflare_pages_domain.site
  to   = module.pages.cloudflare_pages_domain.this
}

moved {
  from = cloudflare_web_analytics_site.site
  to   = module.pages.cloudflare_web_analytics_site.this[0]
}

moved {
  from = ovh_domain_zone_record.www
  to   = module.pages.ovh_domain_zone_record.cname
}
