# www.sylvain.dev : dépôt GitHub site (importé), projet Cloudflare Pages +
# domaine, Web Analytics, et le CNAME OVH qui court-circuite le joker
# *.sylvain.dev vers Pangolin (tofu/dns/pangolin.tf).

mock_provider "github" {}
mock_provider "cloudflare" {}
mock_provider "ovh" {}
mock_provider "sops" {}

# secrets.sops.yaml de la racine : jeton et compte Cloudflare, deploy hook du
# build quotidien (sans lui, le check daily_build_deploy_hook avertit). Ni
# jeton webmention.io ni jeton SonarCloud par défaut.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      CLOUDFLARE_API_TOKEN   = "fake-cloudflare-token"
      CLOUDFLARE_ACCOUNT_ID  = "0123456789abcdef0123456789abcdef"
      SITE_PAGES_DEPLOY_HOOK = "https://example.invalid/fake-deploy-hook"
    }
  }
}

# Le sous-domaine pages.dev est attribué par Cloudflare (<nom>-xxx.pages.dev
# si le nom est pris) : une valeur réaliste pour que la cible du CNAME soit
# connue au plan.
override_resource {
  target = module.pages.cloudflare_pages_project.env_vars
  values = {
    subdomain = "sylvain-dev-9f1.pages.dev"
  }
}

override_resource {
  target = module.pages.cloudflare_web_analytics_site.this
  values = {
    site_token = "fake-beacon-token"
    site_tag   = "fake-site-tag"
  }
}

run "depot_github" {
  command = plan

  assert {
    condition     = module.pages.repository.name == "site" && module.pages.repository.visibility == "public"
    error_message = "Le dépôt site doit être public."
  }

  assert {
    condition     = module.pages.repository.homepage_url == "https://sylvain.dev"
    error_message = "La page d'accueil du dépôt doit être https://sylvain.dev."
  }

  # Comparés au dépôt réel : un topic retiré sur GitHub (hacktoberfest, après
  # octobre 2026) se voyait seulement dans un plan.
  assert {
    condition     = toset(module.pages.repository.topics) == toset(["blog", "eleventy-website", "personal-website", "static-site"])
    error_message = "Les topics du dépôt site ont changé : aligner la config sur le dépôt GitHub."
  }

  assert {
    condition     = module.pages.repository.archive_on_destroy == true
    error_message = "archive_on_destroy doit rester à true."
  }

  assert {
    condition = (
      module.pages.repository.security_and_analysis[0].secret_scanning[0].status == "enabled" &&
      module.pages.repository.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    )
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public site."
  }

  assert {
    condition     = module.pages.vulnerability_alerts.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur site."
  }

  # Renovate gère les montées de version : des PR Dependabot feraient doublon.
  assert {
    condition     = module.pages.dependabot_security_updates.enabled == false
    error_message = "Les mises à jour de sécurité Dependabot doivent rester désactivées sur site : Renovate s'en charge."
  }
}

# PR obligatoire sans approbation (un seul mainteneur), checks verts, ni
# force-push ni suppression ; Sveltia CMS publie en fusionnant ses PR.
run "ruleset_de_main" {
  command = plan

  assert {
    condition = (
      github_repository_ruleset.site_main.repository == module.pages.repository.name &&
      github_repository_ruleset.site_main.target == "branch" &&
      github_repository_ruleset.site_main.enforcement == "active"
    )
    error_message = "Le ruleset doit viser les branches du dépôt site et être actif."
  }

  # Le module pose par défaut une protection de branche classique et restreint
  # le jeton des workflows : le site n'a jamais eu ni l'une ni l'autre.
  assert {
    condition     = module.pages.branch_protection == null && module.pages.workflow_permissions == null
    error_message = "main du dépôt site est protégée par le ruleset seul (protect_production_branch = false), sans restriction du jeton des workflows déclarée (restrict_workflow_token = false)."
  }

  assert {
    condition     = github_repository_ruleset.site_main.conditions[0].ref_name[0].include == tolist(["~DEFAULT_BRANCH"])
    error_message = "Le ruleset doit porter sur la branche par défaut."
  }

  assert {
    condition     = github_repository_ruleset.site_main.rules[0].deletion == true && github_repository_ruleset.site_main.rules[0].non_fast_forward == true
    error_message = "Ni suppression ni force-push de main."
  }

  assert {
    condition     = github_repository_ruleset.site_main.rules[0].pull_request[0].required_approving_review_count == 0
    error_message = "PR obligatoire mais sans approbation : le dépôt n'a qu'un mainteneur."
  }

  assert {
    condition = (
      length(github_repository_ruleset.site_main.rules[0].required_status_checks[0].required_check) == length(var.required_checks) &&
      github_repository_ruleset.site_main.rules[0].required_status_checks[0].strict_required_status_checks_policy == false
    )
    error_message = "Un check requis par contexte de var.required_checks, sans exiger une branche à jour (PR Renovate)."
  }

  # Pas de contournement : Scorecard le pénalise.
  assert {
    condition     = length(github_repository_ruleset.site_main.bypass_actors) == 0
    error_message = "Le ruleset de main ne doit avoir aucun bypass, propriétaire compris."
  }
}

run "projet_cloudflare_pages" {
  command = plan

  # « site » serait trop générique pour le sous-domaine pages.dev.
  assert {
    condition     = module.pages.pages_project.name == "sylvain-dev" && module.pages.pages_project.production_branch == "main"
    error_message = "Le projet Pages doit s'appeler sylvain-dev et déployer main en production."
  }

  assert {
    condition     = module.pages.pages_project.account_id == "0123456789abcdef0123456789abcdef"
    error_message = "Le projet Pages doit être créé dans le compte CLOUDFLARE_ACCOUNT_ID de secrets.sops.yaml."
  }

  assert {
    condition = (
      module.pages.pages_project.source.type == "github" &&
      module.pages.pages_project.source.config.owner == "sylvainmetayer" &&
      module.pages.pages_project.source.config.repo_name == module.pages.repository.name &&
      module.pages.pages_project.source.config.production_branch == "main"
    )
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/site, branche main."
  }

  assert {
    condition     = module.pages.pages_project.build_config.build_command == "npm run production" && module.pages.pages_project.build_config.destination_dir == "dist"
    error_message = "Build Pages : npm run production, sortie dans dist."
  }

  # Pages n'accepte un apex que si la zone est chez Cloudflare.
  assert {
    condition     = module.pages.pages_domain.name == "www.sylvain.dev" && module.pages.pages_domain.project_name == module.pages.pages_project.name
    error_message = "Le domaine personnalisé www.sylvain.dev doit être attaché au projet Pages sylvain-dev."
  }
}

# Avec un jeton webmention.io, il n'existe qu'en production, en secret.
run "jeton_webmention_en_production_seulement" {
  command = plan

  override_data {
    target = data.sops_file.secrets
    values = {
      data = {
        CLOUDFLARE_API_TOKEN     = "fake-cloudflare-token"
        CLOUDFLARE_ACCOUNT_ID    = "0123456789abcdef0123456789abcdef"
        SITE_PAGES_DEPLOY_HOOK   = "https://example.invalid/fake-deploy-hook"
        SITE_WEBMENTION_IO_TOKEN = "fake-webmention-token"
      }
    }
  }

  assert {
    condition     = module.pages.pages_project.env_vars.production["WEBMENTION_IO_TOKEN"].type == "secret_text"
    error_message = "WEBMENTION_IO_TOKEN doit être une variable secrète du déploiement de production."
  }

  assert {
    condition     = try(length(module.pages.pages_project.env_vars.preview), 0) == 0
    error_message = "Les previews ne doivent recevoir aucun jeton webmention.io."
  }

  assert {
    condition     = toset(keys(module.pages.pages_project.env_vars.production)) == toset(["WEBMENTION_IO_TOKEN"])
    error_message = "Sans SITE_CF_ANALYTICS_TOKEN, aucune variable CF_ANALYTICS_* en production."
  }
}

# Avec un jeton Web Analytics en lecture, la liste « les plus lus » reçoit le
# jeton (secret), le compte et le site, en production seulement, à côté du
# jeton webmention.io.
run "les_plus_lus_en_production_seulement" {
  command = plan

  override_data {
    target = data.sops_file.secrets
    values = {
      data = {
        CLOUDFLARE_API_TOKEN     = "fake-cloudflare-token"
        CLOUDFLARE_ACCOUNT_ID    = "0123456789abcdef0123456789abcdef"
        SITE_PAGES_DEPLOY_HOOK   = "https://example.invalid/fake-deploy-hook"
        SITE_WEBMENTION_IO_TOKEN = "fake-webmention-token"
        SITE_CF_ANALYTICS_TOKEN  = "fake-analytics-token"
      }
    }
  }

  assert {
    condition = (
      module.pages.pages_project.env_vars.production["CF_ANALYTICS_TOKEN"].type == "secret_text" &&
      module.pages.pages_project.env_vars.production["CF_ACCOUNT_ID"].value == "0123456789abcdef0123456789abcdef" &&
      module.pages.pages_project.env_vars.production["CF_ANALYTICS_SITE_TAG"].value == "fake-site-tag" &&
      module.pages.pages_project.env_vars.production["WEBMENTION_IO_TOKEN"].type == "secret_text"
    )
    error_message = "La production doit recevoir CF_ANALYTICS_TOKEN (secret), CF_ACCOUNT_ID, CF_ANALYTICS_SITE_TAG et toujours WEBMENTION_IO_TOKEN."
  }

  assert {
    condition     = try(length(module.pages.pages_project.env_vars.preview), 0) == 0
    error_message = "Les previews ne doivent recevoir aucun jeton."
  }
}

# Sans DID, pas d'enregistrement _atproto ; avec, un TXT did=… sur le domaine.
run "handle_bluesky_absent_sans_did" {
  command = plan

  variables {
    bluesky_did = null
  }

  assert {
    condition     = length(ovh_domain_zone_record.atproto) == 0
    error_message = "Sans bluesky_did, aucun enregistrement _atproto."
  }
}

run "handle_bluesky" {
  command = plan

  variables {
    bluesky_did = "did:plc:abcdefghijklmnop"
  }

  assert {
    condition = (
      ovh_domain_zone_record.atproto[0].subdomain == "_atproto" &&
      ovh_domain_zone_record.atproto[0].fieldtype == "TXT" &&
      ovh_domain_zone_record.atproto[0].target == "\"did=did:plc:abcdefghijklmnop\""
    )
    error_message = "Le handle Bluesky se vérifie par un TXT _atproto.sylvain.dev contenant did=<DID>."
  }
}

# sylvain.dev n'est pas une zone Cloudflare : pas d'injection automatique du
# beacon, le site l'insère lui-même avec le jeton exporté.
run "web_analytics" {
  command = plan

  assert {
    condition     = module.pages.web_analytics_site.host == "www.sylvain.dev"
    error_message = "Web Analytics doit suivre l'hôte www.sylvain.dev."
  }

  assert {
    condition     = module.pages.web_analytics_site.auto_install == false
    error_message = "auto_install doit rester à false : sylvain.dev n'est pas une zone Cloudflare."
  }

  assert {
    condition     = output.web_analytics_token == "fake-beacon-token"
    error_message = "La sortie web_analytics_token (cfBeaconToken de site.json) doit être le site_token du site Web Analytics."
  }
}

run "cname_ovh_court_circuite_le_joker" {
  command = plan

  assert {
    condition = (
      module.pages.cname_record.zone == "sylvain.dev" &&
      module.pages.cname_record.subdomain == "www" &&
      module.pages.cname_record.fieldtype == "CNAME"
    )
    error_message = "www.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone.
  assert {
    condition     = module.pages.cname_record.target == "sylvain-dev-9f1.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = module.pages.cname_record.ttl == 300
    error_message = "TTL du CNAME : 300."
  }

  assert {
    condition     = output.pages_subdomain == "sylvain-dev-9f1.pages.dev"
    error_message = "La sortie pages_subdomain doit être le sous-domaine du projet Pages."
  }
}

# Le workflow daily-build du dépôt site lit le deploy hook sous ce nom.
run "deploy_hook_present" {
  command = plan

  assert {
    condition = (
      length(github_actions_secret.pages_deploy_hook) == 1 &&
      github_actions_secret.pages_deploy_hook[0].secret_name == "CLOUDFLARE_PAGES_DEPLOY_HOOK" &&
      github_actions_secret.pages_deploy_hook[0].repository == module.pages.repository.name
    )
    error_message = "Avec SITE_PAGES_DEPLOY_HOOK, le secret CLOUDFLARE_PAGES_DEPLOY_HOOK doit être posé sur le dépôt site."
  }
}

# Absent : pas de secret, et le check daily_build_deploy_hook le signale au
# lieu de laisser le Daily Build échouer chaque matin sans bruit.
run "deploy_hook_absent_signale" {
  command = plan

  override_data {
    target = data.sops_file.secrets
    values = {
      data = {
        CLOUDFLARE_API_TOKEN  = "fake-cloudflare-token"
        CLOUDFLARE_ACCOUNT_ID = "0123456789abcdef0123456789abcdef"
      }
    }
  }

  expect_failures = [check.daily_build_deploy_hook]

  assert {
    condition     = length(github_actions_secret.pages_deploy_hook) == 0
    error_message = "Sans SITE_PAGES_DEPLOY_HOOK, aucun secret GitHub Actions ne doit être créé."
  }
}

run "jeton_sonarcloud_optionnel" {
  command = plan

  assert {
    condition     = length(github_actions_secret.sonar_token) == 0
    error_message = "Sans SITE_SONAR_TOKEN, aucun secret SONAR_TOKEN ne doit être créé."
  }
}

run "jeton_sonarcloud_present" {
  command = plan

  override_data {
    target = data.sops_file.secrets
    values = {
      data = {
        CLOUDFLARE_API_TOKEN   = "fake-cloudflare-token"
        CLOUDFLARE_ACCOUNT_ID  = "0123456789abcdef0123456789abcdef"
        SITE_PAGES_DEPLOY_HOOK = "https://example.invalid/fake-deploy-hook"
        SITE_SONAR_TOKEN       = "fake-sonar-token"
      }
    }
  }

  assert {
    condition = (
      length(github_actions_secret.sonar_token) == 1 &&
      github_actions_secret.sonar_token[0].secret_name == "SONAR_TOKEN" &&
      github_actions_secret.sonar_token[0].repository == module.pages.repository.name
    )
    error_message = "Avec SITE_SONAR_TOKEN, le secret SONAR_TOKEN doit être posé sur le dépôt site."
  }
}

run "app_cloudflare_absente_par_defaut" {
  command = plan

  assert {
    condition     = length(module.pages.cloudflare_app_installation) == 0
    error_message = "Sans cloudflare_github_installation_id, aucun accès d'app GitHub ne doit être posé."
  }
}

run "app_cloudflare_en_mode_depots_choisis" {
  command = plan

  variables {
    cloudflare_github_installation_id = 12345678
  }

  assert {
    condition = (
      length(module.pages.cloudflare_app_installation) == 1 &&
      tostring(module.pages.cloudflare_app_installation[0].installation_id) == "12345678" &&
      module.pages.cloudflare_app_installation[0].repository == module.pages.repository.name
    )
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt site."
  }
}
