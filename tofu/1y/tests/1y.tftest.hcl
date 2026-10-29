# r.sylvain.dev (raccourcisseur d'URL 11ty) : dépôt GitHub 1y importé, projet
# Cloudflare Pages + domaine, et le CNAME OVH qui court-circuite le joker
# *.sylvain.dev vers Pangolin (tofu/dns/pangolin.tf).

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

# mise.toml et wrangler.toml de la branche de production, d'accord sur la
# version de Node : la postcondition de data.github_repository_file.wrangler
# (node.tf) passe.
override_data {
  target = data.github_repository_file.mise
  values = {
    content = "[tools]\nnode = \"22.12.0\"\n\n[env]\n_.path = [\"node_modules/.bin\"]\n"
  }
}

override_data {
  target = data.github_repository_file.wrangler
  values = {
    content = "name = \"1y\"\npages_build_output_dir = \"_site\"\n\n[vars]\nNODE_VERSION = \"22.12.0\"\n"
  }
}

# Le sous-domaine pages.dev est attribué par Cloudflare (<nom>-xxx.pages.dev
# si le nom est pris) : une valeur réaliste pour que la cible du CNAME soit
# connue au plan.
override_resource {
  target = module.pages.cloudflare_pages_project.wrangler
  values = {
    subdomain = "1y-7c2.pages.dev"
  }
}

run "depot_github_importe" {
  command = plan

  assert {
    condition     = module.pages.repository.name == "1y" && module.pages.repository.visibility == "public"
    error_message = "Le dépôt 1y doit être public."
  }

  assert {
    condition     = module.pages.repository.homepage_url == "https://r.sylvain.dev"
    error_message = "La page d'accueil du dépôt doit être https://r.sylvain.dev."
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
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public 1y."
  }

  assert {
    condition     = module.pages.vulnerability_alerts.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur 1y."
  }

  # Renovate gère les montées de version : des PR Dependabot feraient doublon.
  assert {
    condition     = module.pages.dependabot_security_updates.enabled == false
    error_message = "Les mises à jour de sécurité Dependabot doivent rester désactivées sur 1y : Renovate s'en charge."
  }

  assert {
    condition = (
      module.pages.workflow_permissions.default_workflow_permissions == "read"
      && module.pages.workflow_permissions.can_approve_pull_request_reviews == false
    )
    error_message = "Le jeton des workflows de 1y doit rester en lecture seule, sans droit d'approuver une PR."
  }
}

# Les liens s'ajoutent en poussant sur master : pas de PR obligatoire, seulement
# une protection contre la perte d'historique, propriétaire compris.
run "protection_de_master_sans_pr" {
  command = plan

  assert {
    condition     = module.pages.branch_protection.pattern == "master"
    error_message = "La protection doit porter sur master, la branche de production."
  }

  assert {
    condition     = module.pages.branch_protection.repository_id == module.pages.repository.node_id
    error_message = "La protection doit viser le node_id de module.pages.repository."
  }

  assert {
    condition     = length(module.pages.branch_protection.required_pull_request_reviews) == 0
    error_message = "Aucune PR ne doit être exigée sur master."
  }

  assert {
    condition     = module.pages.branch_protection.allows_force_pushes == false && module.pages.branch_protection.allows_deletions == false
    error_message = "Ni force-push ni suppression de master."
  }

  assert {
    condition     = module.pages.branch_protection.enforce_admins == true
    error_message = "enforce_admins doit rester à true : sans lui, la protection ne s'applique pas au seul qui pousse."
  }
}

run "projet_cloudflare_pages" {
  command = plan

  assert {
    condition     = module.pages.pages_project.name == "1y" && module.pages.pages_project.production_branch == "master"
    error_message = "Le projet Pages doit s'appeler comme le dépôt et déployer master en production."
  }

  assert {
    condition     = module.pages.pages_project.account_id == "0123456789abcdef0123456789abcdef"
    error_message = "Le projet Pages doit être créé dans le compte CLOUDFLARE_ACCOUNT_ID de secrets.sops.yaml."
  }

  # Web Analytics est activé par défaut dans le module : 1y n'en a jamais eu.
  assert {
    condition     = module.pages.web_analytics_site == null
    error_message = "Pas de site Web Analytics pour 1y (web_analytics = false dans main.tf) : aucune page ne chargerait le beacon."
  }

  assert {
    condition = (
      module.pages.pages_project.source.type == "github" &&
      module.pages.pages_project.source.config.owner == "sylvainmetayer" &&
      module.pages.pages_project.source.config.repo_name == "1y" &&
      module.pages.pages_project.source.config.production_branch == "master"
    )
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/1y, branche master."
  }

  # Sortie d'Eleventy.
  assert {
    condition     = module.pages.pages_project.build_config.build_command == "npm run build" && module.pages.pages_project.build_config.destination_dir == "_site"
    error_message = "Build Pages : npm run build, sortie dans _site (Eleventy)."
  }

  assert {
    condition     = module.pages.pages_domain.name == "r.sylvain.dev" && module.pages.pages_domain.project_name == module.pages.pages_project.name
    error_message = "Le domaine personnalisé r.sylvain.dev doit être attaché au projet Pages 1y."
  }
}

# Pages ne lit que le NODE_VERSION de wrangler.toml : une version de Node
# montée dans mise.toml seule doit bloquer le plan.
run "node_desynchronise_bloque_le_plan" {
  command = plan

  override_data {
    target = data.github_repository_file.wrangler
    values = {
      content = "name = \"1y\"\npages_build_output_dir = \"_site\"\n\n[vars]\nNODE_VERSION = \"20.18.0\"\n"
    }
  }

  expect_failures = [data.github_repository_file.wrangler]
}

# Absente de wrangler.toml, la version retombe sur le défaut de l'image de
# build Pages, quelle qu'elle soit : bloquant aussi.
run "node_absent_de_wrangler_bloque_le_plan" {
  command = plan

  override_data {
    target = data.github_repository_file.wrangler
    values = {
      content = "name = \"1y\"\npages_build_output_dir = \"_site\"\n"
    }
  }

  expect_failures = [data.github_repository_file.wrangler]
}

# Sans version dans mise.toml, rien à comparer : « introuvable » des deux
# côtés ne doit pas passer pour un accord.
run "node_absent_des_deux_bloque_le_plan" {
  command = plan

  override_data {
    target = data.github_repository_file.mise
    values = {
      content = "[tools]\npython = \"3.14\"\n"
    }
  }

  override_data {
    target = data.github_repository_file.wrangler
    values = {
      content = "name = \"1y\"\n"
    }
  }

  expect_failures = [data.github_repository_file.wrangler]
}

run "fichiers_lus_sur_la_branche_de_production" {
  command = plan

  variables {
    production_branch = "main"
  }

  assert {
    condition = (
      data.github_repository_file.mise.branch == "main" &&
      data.github_repository_file.wrangler.branch == "main" &&
      module.pages.pages_project.production_branch == "main" &&
      module.pages.pages_project.source.config.production_branch == "main" &&
      module.pages.branch_protection.pattern == "main"
    )
    error_message = "Projet Pages, protection de branche et fichiers lus par la postcondition doivent tous suivre var.production_branch."
  }
}

run "cname_ovh_court_circuite_le_joker" {
  command = plan

  assert {
    condition = (
      module.pages.cname_record.zone == "sylvain.dev" &&
      module.pages.cname_record.subdomain == "r" &&
      module.pages.cname_record.fieldtype == "CNAME"
    )
    error_message = "r.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone.
  assert {
    condition     = module.pages.cname_record.target == "1y-7c2.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = module.pages.cname_record.ttl == 300
    error_message = "TTL du CNAME : 300."
  }

  assert {
    condition     = output.pages_subdomain == "1y-7c2.pages.dev"
    error_message = "La sortie pages_subdomain doit être le sous-domaine du projet Pages."
  }
}

# Mode « All repositories » ou installation pas encore faite : rien à poser.
run "apps_github_absentes_par_defaut" {
  command = plan

  assert {
    condition     = length(module.pages.cloudflare_app_installation) == 0 && length(github_app_installation_repository.renovate) == 0
    error_message = "Sans ID d'installation, aucun accès d'app GitHub ne doit être posé."
  }
}

run "apps_github_en_mode_depots_choisis" {
  command = plan

  variables {
    cloudflare_github_installation_id = 12345678
    renovate_github_installation_id   = 87654321
  }

  assert {
    condition = (
      length(module.pages.cloudflare_app_installation) == 1 &&
      tostring(module.pages.cloudflare_app_installation[0].installation_id) == "12345678" &&
      module.pages.cloudflare_app_installation[0].repository == module.pages.repository.name
    )
    error_message = "Avec cloudflare_github_installation_id, l'app Cloudflare doit recevoir l'accès au dépôt 1y."
  }

  assert {
    condition = (
      length(github_app_installation_repository.renovate) == 1 &&
      tostring(github_app_installation_repository.renovate[0].installation_id) == "87654321" &&
      github_app_installation_repository.renovate[0].repository == module.pages.repository.name
    )
    error_message = "Avec renovate_github_installation_id, l'app Renovate doit recevoir l'accès au dépôt 1y."
  }
}

# Un seul hôte (local.hostname) pilote le domaine Pages, le CNAME, la page
# d'accueil et la description du dépôt.
run "sous_domaine_coherent_partout" {
  command = plan

  variables {
    subdomain = "go"
  }

  assert {
    condition = (
      module.pages.pages_domain.name == "go.sylvain.dev" &&
      module.pages.cname_record.subdomain == "go" &&
      module.pages.repository.homepage_url == "https://go.sylvain.dev" &&
      endswith(module.pages.repository.description, "go.sylvain.dev")
    )
    error_message = "Domaine Pages, CNAME, page d'accueil et description du dépôt doivent tous suivre var.subdomain."
  }
}
