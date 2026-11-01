# planning.sylvain.dev : vitrine statique de planning-equipes (dossier site/ du
# dépôt, géré par tofu/github), projet Cloudflare Pages + domaine, Web
# Analytics, et le CNAME OVH qui court-circuite le joker *.sylvain.dev vers
# Pangolin (tofu/dns/pangolin.tf).

mock_provider "github" {}
mock_provider "cloudflare" {}
mock_provider "ovh" {}
mock_provider "sops" {}

# secrets/secrets.sops.yaml : jeton et compte Cloudflare (secrets.tf).
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      CLOUDFLARE_API_TOKEN  = "fake-cloudflare-token"
      CLOUDFLARE_ACCOUNT_ID = "0123456789abcdef0123456789abcdef"
    }
  }
}

# Le sous-domaine pages.dev est attribué par Cloudflare (<nom>-xxx.pages.dev
# si le nom est pris) : une valeur réaliste pour que la cible du CNAME soit
# connue au plan.
override_resource {
  target = cloudflare_pages_project.planning
  values = {
    subdomain = "planning-equipes-3f1.pages.dev"
  }
}

override_resource {
  target = cloudflare_web_analytics_site.planning
  values = {
    site_tag   = "fake-site-tag"
    site_token = "fake-beacon-token"
  }
}

# Les deux pages, à jour : leur beacon porte le jeton du site Web Analytics.
override_data {
  target = data.github_repository_file.beacon_pages
  values = {
    content = "<script defer src=\"https://static.cloudflareinsights.com/beacon.min.js\" data-cf-beacon='{\"token\": \"fake-beacon-token\"}'></script>"
  }
}

run "projet_cloudflare_pages" {
  command = plan

  assert {
    condition     = cloudflare_pages_project.planning.name == "planning-equipes" && cloudflare_pages_project.planning.production_branch == "main"
    error_message = "Le projet Pages doit s'appeler comme le dépôt (et le name de site/wrangler.toml) et déployer main en production."
  }

  assert {
    condition     = cloudflare_pages_project.planning.account_id == "0123456789abcdef0123456789abcdef"
    error_message = "Le projet Pages doit être créé dans le compte CLOUDFLARE_ACCOUNT_ID de secrets/secrets.sops.yaml."
  }

  assert {
    condition = (
      cloudflare_pages_project.planning.source.type == "github" &&
      cloudflare_pages_project.planning.source.config.owner == "sylvainmetayer" &&
      cloudflare_pages_project.planning.source.config.repo_name == "planning-equipes" &&
      cloudflare_pages_project.planning.source.config.production_branch == "main"
    )
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/planning-equipes, branche main."
  }

  # Comme tofu/ref : un aperçu par branche, commenté sur la PR.
  assert {
    condition = (
      cloudflare_pages_project.planning.source.config.preview_deployment_setting == "all" &&
      cloudflare_pages_project.planning.source.config.pr_comments_enabled == true &&
      cloudflare_pages_project.planning.source.config.production_deployments_enabled == true
    )
    error_message = "Production à chaque merge sur main, aperçu sur chaque branche avec commentaire de PR (comme tofu/ref)."
  }

  # Un commit de l'application ne doit pas redéployer la vitrine.
  assert {
    condition     = cloudflare_pages_project.planning.source.config.path_includes == tolist(["site/**"])
    error_message = "Seuls les changements sous site/ doivent déclencher un build Pages."
  }

  # Site statique : pas de build, site/ publié tel quel (pages_build_output_dir
  # = "." dans site/wrangler.toml).
  assert {
    condition = (
      cloudflare_pages_project.planning.build_config.build_command == "" &&
      cloudflare_pages_project.planning.build_config.destination_dir == "." &&
      cloudflare_pages_project.planning.build_config.root_dir == "site"
    )
    error_message = "Build Pages : aucune commande, dossier racine site, sortie « . »."
  }

  assert {
    condition     = cloudflare_pages_domain.planning.name == "planning.sylvain.dev" && cloudflare_pages_domain.planning.project_name == cloudflare_pages_project.planning.name
    error_message = "Le domaine personnalisé planning.sylvain.dev doit être attaché au projet Pages planning-equipes."
  }
}

# sylvain.dev n'est pas une zone Cloudflare : pas d'injection automatique du
# beacon, les pages l'insèrent elles-mêmes avec le jeton exporté.
run "web_analytics" {
  command = plan

  assert {
    condition     = cloudflare_web_analytics_site.planning.host == "planning.sylvain.dev"
    error_message = "Web Analytics doit suivre l'hôte planning.sylvain.dev."
  }

  assert {
    condition     = cloudflare_web_analytics_site.planning.auto_install == false
    error_message = "auto_install doit rester à false : sylvain.dev n'est pas une zone Cloudflare."
  }

  assert {
    condition     = output.web_analytics_token == "fake-beacon-token" && output.web_analytics_site_tag == "fake-site-tag"
    error_message = "Les sorties web_analytics_token et web_analytics_site_tag doivent être celles du site Web Analytics."
  }

  assert {
    condition     = toset(keys(data.github_repository_file.beacon_pages)) == toset(["index.html", "en/index.html"])
    error_message = "Le check beacon_token doit lire les deux pages, française et anglaise."
  }

  assert {
    condition = alltrue([
      for p in data.github_repository_file.beacon_pages :
      p.repository == "planning-equipes" && p.branch == "main" && startswith(p.file, "site/")
    ])
    error_message = "Les pages lues doivent être celles de site/ sur main du dépôt planning-equipes."
  }
}

# Jeton pas encore recopié (le placeholder de la PR planning-equipes) ou site
# Web Analytics recréé : le check beacon_token doit le signaler.
run "jeton_beacon_absent_signale" {
  command = plan

  override_data {
    target = data.github_repository_file.beacon_pages
    values = {
      content = "<script defer src=\"https://static.cloudflareinsights.com/beacon.min.js\" data-cf-beacon='{\"token\": \"A_REMPLACER_PAR_LE_JETON\"}'></script>"
    }
  }

  expect_failures = [check.beacon_token]
}

# Une seule page à jour (la française), l'anglaise encore au jeton factice :
# le check doit exiger les deux.
run "jeton_beacon_sur_une_seule_page_signale" {
  command = plan

  override_data {
    target = data.github_repository_file.beacon_pages["en/index.html"]
    values = {
      content = "<script defer src=\"https://static.cloudflareinsights.com/beacon.min.js\" data-cf-beacon='{\"token\": \"A_REMPLACER_PAR_LE_JETON\"}'></script>"
    }
  }

  expect_failures = [check.beacon_token]
}

# Le jeton présent ailleurs que dans data-cf-beacon (un commentaire) ne
# suffit pas.
run "jeton_hors_du_beacon_signale" {
  command = plan

  override_data {
    target = data.github_repository_file.beacon_pages
    values = {
      content = "<!-- fake-beacon-token --><script defer src=\"https://static.cloudflareinsights.com/beacon.min.js\" data-cf-beacon='{\"token\": \"A_REMPLACER_PAR_LE_JETON\"}'></script>"
    }
  }

  expect_failures = [check.beacon_token]
}

run "cname_ovh_court_circuite_le_joker" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.planning.zone == "sylvain.dev" &&
      ovh_domain_zone_record.planning.subdomain == "planning" &&
      ovh_domain_zone_record.planning.fieldtype == "CNAME"
    )
    error_message = "planning.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone :
  # planning-equipes-3f1.pages.dev.sylvain.dev.
  assert {
    condition     = ovh_domain_zone_record.planning.target == "planning-equipes-3f1.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = ovh_domain_zone_record.planning.ttl == 300
    error_message = "TTL du CNAME : 300."
  }

  assert {
    condition     = output.pages_subdomain == "planning-equipes-3f1.pages.dev"
    error_message = "La sortie pages_subdomain doit être le sous-domaine du projet Pages."
  }
}

# Mode « All repositories » : rien à poser.
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
      github_app_installation_repository.cloudflare[0].repository == "planning-equipes"
    )
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt planning-equipes."
  }
}

# Un seul hôte (local.hostname) pilote le domaine Pages, Web Analytics et le
# CNAME : changer le sous-domaine les déplace ensemble.
run "sous_domaine_coherent_partout" {
  command = plan

  variables {
    subdomain = "vitrine"
  }

  assert {
    condition = (
      cloudflare_pages_domain.planning.name == "vitrine.sylvain.dev" &&
      cloudflare_web_analytics_site.planning.host == "vitrine.sylvain.dev" &&
      ovh_domain_zone_record.planning.subdomain == "vitrine"
    )
    error_message = "Domaine Pages, Web Analytics et CNAME doivent tous suivre var.subdomain."
  }
}
