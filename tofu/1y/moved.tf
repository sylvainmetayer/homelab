# Ressources passées dans le module commun tofu/modules/pages_site (2026-10-29).
# À garder tant que l'état n'a pas été appliqué avec ces adresses. Le bloc
# import du dépôt, devenu sans objet (dépôt dans l'état), est parti avec.

moved {
  from = github_repository.r
  to   = module.pages.github_repository.this
}

moved {
  from = github_repository_vulnerability_alerts.r
  to   = module.pages.github_repository_vulnerability_alerts.this
}

moved {
  from = github_repository_dependabot_security_updates.r
  to   = module.pages.github_repository_dependabot_security_updates.this
}

moved {
  from = github_workflow_repository_permissions.r
  to   = module.pages.github_workflow_repository_permissions.this[0]
}

moved {
  from = github_branch_protection.r_master
  to   = module.pages.github_branch_protection.production[0]
}

moved {
  from = github_app_installation_repository.cloudflare
  to   = module.pages.github_app_installation_repository.cloudflare
}

moved {
  from = cloudflare_pages_project.r
  to   = module.pages.cloudflare_pages_project.wrangler[0]
}

moved {
  from = cloudflare_pages_domain.r
  to   = module.pages.cloudflare_pages_domain.this
}

moved {
  from = ovh_domain_zone_record.r
  to   = module.pages.ovh_domain_zone_record.cname
}
