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
  target = cloudflare_pages_project.site
  values = {
    subdomain = "sylvain-dev-9f1.pages.dev"
  }
}

override_resource {
  target = cloudflare_web_analytics_site.site
  values = {
    site_token = "fake-beacon-token"
  }
}

run "depot_github" {
  command = plan

  assert {
    condition     = github_repository.site.name == "site" && github_repository.site.visibility == "public"
    error_message = "Le dépôt site doit être public."
  }

  assert {
    condition     = github_repository.site.homepage_url == "https://sylvain.dev"
    error_message = "La page d'accueil du dépôt doit être https://sylvain.dev."
  }

  assert {
    condition     = github_repository.site.archive_on_destroy == true
    error_message = "archive_on_destroy doit rester à true."
  }

  assert {
    condition = (
      github_repository.site.security_and_analysis[0].secret_scanning[0].status == "enabled" &&
      github_repository.site.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    )
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public site."
  }

  assert {
    condition     = github_repository_vulnerability_alerts.site.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur site."
  }

  # Renovate gère les montées de version : des PR Dependabot feraient doublon.
  assert {
    condition     = github_repository_dependabot_security_updates.site.enabled == false
    error_message = "Les mises à jour de sécurité Dependabot doivent rester désactivées sur site : Renovate s'en charge."
  }
}

# PR obligatoire sans approbation (un seul mainteneur), checks verts, ni
# force-push ni suppression ; Sveltia CMS publie en fusionnant ses PR.
run "ruleset_de_main" {
  command = plan

  assert {
    condition = (
      github_repository_ruleset.site_main.repository == github_repository.site.name &&
      github_repository_ruleset.site_main.target == "branch" &&
      github_repository_ruleset.site_main.enforcement == "active"
    )
    error_message = "Le ruleset doit viser les branches du dépôt site et être actif."
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
    condition     = cloudflare_pages_project.site.name == "sylvain-dev" && cloudflare_pages_project.site.production_branch == "main"
    error_message = "Le projet Pages doit s'appeler sylvain-dev et déployer main en production."
  }

  assert {
    condition     = cloudflare_pages_project.site.account_id == "0123456789abcdef0123456789abcdef"
    error_message = "Le projet Pages doit être créé dans le compte CLOUDFLARE_ACCOUNT_ID de secrets.sops.yaml."
  }

  assert {
    condition = (
      cloudflare_pages_project.site.source.type == "github" &&
      cloudflare_pages_project.site.source.config.owner == "sylvainmetayer" &&
      cloudflare_pages_project.site.source.config.repo_name == github_repository.site.name &&
      cloudflare_pages_project.site.source.config.production_branch == "main"
    )
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/site, branche main."
  }

  assert {
    condition     = cloudflare_pages_project.site.build_config.build_command == "npm run production" && cloudflare_pages_project.site.build_config.destination_dir == "dist"
    error_message = "Build Pages : npm run production, sortie dans dist."
  }

  # Pages n'accepte un apex que si la zone est chez Cloudflare.
  assert {
    condition     = cloudflare_pages_domain.site.name == "www.sylvain.dev" && cloudflare_pages_domain.site.project_name == cloudflare_pages_project.site.name
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
    condition     = cloudflare_pages_project.site.deployment_configs.production.env_vars["WEBMENTION_IO_TOKEN"].type == "secret_text"
    error_message = "WEBMENTION_IO_TOKEN doit être une variable secrète du déploiement de production."
  }

  assert {
    condition     = try(length(cloudflare_pages_project.site.deployment_configs.preview.env_vars), 0) == 0
    error_message = "Les previews ne doivent recevoir aucun jeton webmention.io."
  }
}

# sylvain.dev n'est pas une zone Cloudflare : pas d'injection automatique du
# beacon, le site l'insère lui-même avec le jeton exporté.
run "web_analytics" {
  command = plan

  assert {
    condition     = cloudflare_web_analytics_site.site.host == "www.sylvain.dev"
    error_message = "Web Analytics doit suivre l'hôte www.sylvain.dev."
  }

  assert {
    condition     = cloudflare_web_analytics_site.site.auto_install == false
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
      ovh_domain_zone_record.www.zone == "sylvain.dev" &&
      ovh_domain_zone_record.www.subdomain == "www" &&
      ovh_domain_zone_record.www.fieldtype == "CNAME"
    )
    error_message = "www.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone.
  assert {
    condition     = ovh_domain_zone_record.www.target == "sylvain-dev-9f1.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = ovh_domain_zone_record.www.ttl == 300
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
      github_actions_secret.pages_deploy_hook[0].repository == github_repository.site.name
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
      github_actions_secret.sonar_token[0].repository == github_repository.site.name
    )
    error_message = "Avec SITE_SONAR_TOKEN, le secret SONAR_TOKEN doit être posé sur le dépôt site."
  }
}

run "app_cloudflare_absente_par_defaut" {
  command = plan

  assert {
    condition     = length(github_app_installation_repository.cloudflare) == 0
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
      length(github_app_installation_repository.cloudflare) == 1 &&
      tostring(github_app_installation_repository.cloudflare[0].installation_id) == "12345678" &&
      github_app_installation_repository.cloudflare[0].repository == github_repository.site.name
    )
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt site."
  }
}
