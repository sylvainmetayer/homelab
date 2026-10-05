# www.sylvain.dev : projet Cloudflare Pages + domaine, Web Analytics, et le
# CNAME OVH qui court-circuite le joker *.sylvain.dev vers Pangolin
# (tofu/dns/pangolin.tf). Le dépôt site est seulement lu, pas géré.

mock_provider "github" {}
mock_provider "cloudflare" {}
mock_provider "ovh" {}
mock_provider "sops" {}

# secrets.sops.yaml de la racine : jeton et compte Cloudflare (secrets.tf), sans
# deploy hook par défaut.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      CLOUDFLARE_API_TOKEN  = "fake-cloudflare-token"
      CLOUDFLARE_ACCOUNT_ID = "0123456789abcdef0123456789abcdef"
    }
  }
}

override_data {
  target = data.github_repository.site
  values = {
    name = "site"
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

run "depot_lu_et_non_gere" {
  command = plan

  assert {
    condition     = data.github_repository.site.full_name == "sylvainmetayer/site"
    error_message = "Le module doit lire le dépôt sylvainmetayer/site, sans le gérer."
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
      cloudflare_pages_project.site.source.config.repo_name == data.github_repository.site.name &&
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

# Deploy hook absent de secrets.sops.yaml : pas de secret GitHub Actions.
run "deploy_hook_absent" {
  command = plan

  assert {
    condition     = length(github_actions_secret.pages_deploy_hook) == 0
    error_message = "Sans SITE_PAGES_DEPLOY_HOOK, aucun secret GitHub Actions ne doit être créé."
  }
}

# Présent : le workflow daily-build du dépôt site le lit sous ce nom.
run "deploy_hook_present" {
  command = plan

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

  assert {
    condition = (
      length(github_actions_secret.pages_deploy_hook) == 1 &&
      github_actions_secret.pages_deploy_hook[0].secret_name == "CLOUDFLARE_PAGES_DEPLOY_HOOK" &&
      github_actions_secret.pages_deploy_hook[0].repository == "site"
    )
    error_message = "Avec SITE_PAGES_DEPLOY_HOOK, le secret CLOUDFLARE_PAGES_DEPLOY_HOOK doit être posé sur le dépôt site."
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
      github_app_installation_repository.cloudflare[0].repository == "site"
    )
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt site."
  }
}
