# ref.sylvain.dev : dépôt GitHub, projet Cloudflare Pages + domaine, Web
# Analytics, et le CNAME OVH qui court-circuite le joker *.sylvain.dev vers
# Pangolin (tofu/dns/pangolin.tf).

mock_provider "github" {}
mock_provider "cloudflare" {}
mock_provider "ovh" {}
mock_provider "sops" {}

# secrets.sops.yaml de la racine : jeton et compte Cloudflare (secrets.tf).
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
  target = module.pages.cloudflare_pages_project.wrangler
  values = {
    subdomain = "ref-4ab.pages.dev"
  }
}

override_resource {
  target = module.pages.cloudflare_web_analytics_site.this
  values = {
    site_token = "fake-beacon-token"
  }
}

# src/_data/site.json du dépôt ref, lu par le check beacon_token : à jour, il
# porte le jeton du site Web Analytics.
override_data {
  target = data.github_repository_file.site_json
  values = {
    content = "{\"title\": \"Parrainage\", \"cfBeaconToken\": \"fake-beacon-token\"}"
  }
}

run "depot_github" {
  command = plan

  assert {
    condition     = module.pages.repository.name == "ref" && module.pages.repository.visibility == "public"
    error_message = "Le dépôt ref doit être public."
  }

  # Poussé à la main depuis ~/Documents/ref : un commit racine auto-généré
  # serait étranger à cet historique.
  assert {
    condition     = module.pages.repository.auto_init == false
    error_message = "auto_init doit rester à false : l'historique du site est poussé à la main."
  }

  assert {
    condition     = module.pages.repository.homepage_url == "https://ref.sylvain.dev"
    error_message = "La page d'accueil du dépôt doit être https://ref.sylvain.dev."
  }

  # Le pied de page du site renvoie vers /issues/new.
  assert {
    condition     = module.pages.repository.has_issues == true
    error_message = "Les issues doivent rester ouvertes : le pied de page du site renvoie vers /issues/new."
  }

  assert {
    condition     = module.pages.repository.allow_merge_commit == false && module.pages.repository.delete_branch_on_merge == true
    error_message = "Pas de merge commit, branches supprimées après fusion."
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
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public ref."
  }

  assert {
    condition     = module.pages.vulnerability_alerts.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur ref."
  }

  assert {
    condition     = module.pages.dependabot_security_updates.enabled == true
    error_message = "Les mises à jour de sécurité Dependabot doivent rester activées sur ref."
  }

  # Dépôt public : un workflow ajouté plus tard sans bloc `permissions:` ne
  # doit rien pouvoir y écrire.
  assert {
    condition = (
      module.pages.workflow_permissions.default_workflow_permissions == "read"
      && module.pages.workflow_permissions.can_approve_pull_request_reviews == false
    )
    error_message = "Le jeton des workflows de ref doit rester en lecture seule, sans droit d'approuver une PR."
  }
}

# Sveltia CMS commite directement sur main depuis le téléphone : pas de PR
# obligatoire, seulement une protection contre la perte d'historique.
run "protection_de_main_sans_pr" {
  command = plan

  assert {
    condition     = module.pages.branch_protection.pattern == "main"
    error_message = "La protection doit porter sur main."
  }

  assert {
    condition     = module.pages.branch_protection.repository_id == module.pages.repository.node_id
    error_message = "La protection doit viser le node_id de module.pages.repository."
  }

  assert {
    condition     = length(module.pages.branch_protection.required_pull_request_reviews) == 0
    error_message = "Aucune PR ne doit être exigée sur main : Sveltia CMS y commite directement."
  }

  assert {
    condition     = module.pages.branch_protection.allows_force_pushes == false && module.pages.branch_protection.allows_deletions == false
    error_message = "Ni force-push ni suppression de main."
  }

  # Le propriétaire est le seul à pousser : la protection doit aussi le viser.
  assert {
    condition     = module.pages.branch_protection.enforce_admins == true
    error_message = "enforce_admins doit rester à true : sans lui, la protection ne s'applique pas au seul qui pousse."
  }
}

run "projet_cloudflare_pages" {
  command = plan

  assert {
    condition     = module.pages.pages_project.name == "ref" && module.pages.pages_project.production_branch == "main"
    error_message = "Le projet Pages doit s'appeler comme le dépôt et déployer main en production."
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
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/ref, branche main."
  }

  # Sortie d'Eleventy.
  assert {
    condition     = module.pages.pages_project.build_config.build_command == "npm run build" && module.pages.pages_project.build_config.destination_dir == "_site"
    error_message = "Build Pages : npm run build, sortie dans _site (Eleventy)."
  }

  assert {
    condition     = module.pages.pages_domain.name == "ref.sylvain.dev" && module.pages.pages_domain.project_name == module.pages.pages_project.name
    error_message = "Le domaine personnalisé ref.sylvain.dev doit être attaché au projet Pages ref."
  }
}

# sylvain.dev n'est pas une zone Cloudflare : pas d'injection automatique du
# beacon, le site l'insère lui-même avec le jeton exporté.
run "web_analytics" {
  command = plan

  assert {
    condition     = module.pages.web_analytics_site.host == "ref.sylvain.dev"
    error_message = "Web Analytics doit suivre l'hôte ref.sylvain.dev."
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

# Site Web Analytics recréé (nouveau jeton) sans recopier le jeton dans
# site.json : le check beacon_token doit le signaler au lieu de laisser les
# pages vues se perdre sans bruit.
run "jeton_beacon_desynchronise_signale" {
  command = plan

  override_data {
    target = data.github_repository_file.site_json
    values = {
      content = "{\"title\": \"Parrainage\", \"cfBeaconToken\": \"ancien-jeton\"}"
    }
  }

  expect_failures = [check.beacon_token]
}

run "cname_ovh_court_circuite_le_joker" {
  command = plan

  assert {
    condition = (
      module.pages.cname_record.zone == "sylvain.dev" &&
      module.pages.cname_record.subdomain == "ref" &&
      module.pages.cname_record.fieldtype == "CNAME"
    )
    error_message = "ref.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone :
  # ref-4ab.pages.dev.sylvain.dev.
  assert {
    condition     = module.pages.cname_record.target == "ref-4ab.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = module.pages.cname_record.ttl == 300
    error_message = "TTL du CNAME : 300."
  }

  assert {
    condition     = output.pages_subdomain == "ref-4ab.pages.dev"
    error_message = "La sortie pages_subdomain doit être le sous-domaine du projet Pages."
  }
}

# Mode « All repositories » ou installation pas encore faite : rien à poser.
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
    condition     = length(module.pages.cloudflare_app_installation) == 1
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt."
  }

  assert {
    condition = (
      tostring(module.pages.cloudflare_app_installation[0].installation_id) == "12345678" &&
      module.pages.cloudflare_app_installation[0].repository == module.pages.repository.name
    )
    error_message = "L'accès doit être donné à l'installation indiquée, sur le dépôt ref."
  }
}

# Un seul hôte (local.hostname) pilote le domaine Pages, Web Analytics, le
# CNAME et la page d'accueil du dépôt : changer le sous-domaine les déplace
# tous ensemble.
run "sous_domaine_coherent_partout" {
  command = plan

  variables {
    subdomain = "parrainage"
  }

  assert {
    condition = (
      module.pages.pages_domain.name == "parrainage.sylvain.dev" &&
      module.pages.web_analytics_site.host == "parrainage.sylvain.dev" &&
      module.pages.cname_record.subdomain == "parrainage" &&
      module.pages.repository.homepage_url == "https://parrainage.sylvain.dev"
    )
    error_message = "Domaine Pages, Web Analytics, CNAME et page d'accueil doivent tous suivre var.subdomain."
  }
}
