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
  target = cloudflare_pages_project.ref
  values = {
    subdomain = "ref-4ab.pages.dev"
  }
}

override_resource {
  target = cloudflare_web_analytics_site.ref
  values = {
    site_token = "fake-beacon-token"
  }
}

run "depot_github" {
  command = plan

  assert {
    condition     = github_repository.ref.name == "ref" && github_repository.ref.visibility == "public"
    error_message = "Le dépôt ref doit être public."
  }

  # Poussé à la main depuis ~/Documents/ref : un commit racine auto-généré
  # serait étranger à cet historique.
  assert {
    condition     = github_repository.ref.auto_init == false
    error_message = "auto_init doit rester à false : l'historique du site est poussé à la main."
  }

  assert {
    condition     = github_repository.ref.homepage_url == "https://ref.sylvain.dev"
    error_message = "La page d'accueil du dépôt doit être https://ref.sylvain.dev."
  }

  # Le pied de page du site renvoie vers /issues/new.
  assert {
    condition     = github_repository.ref.has_issues == true
    error_message = "Les issues doivent rester ouvertes : le pied de page du site renvoie vers /issues/new."
  }

  assert {
    condition     = github_repository.ref.allow_merge_commit == false && github_repository.ref.delete_branch_on_merge == true
    error_message = "Pas de merge commit, branches supprimées après fusion."
  }

  assert {
    condition     = github_repository.ref.archive_on_destroy == true
    error_message = "archive_on_destroy doit rester à true."
  }

  assert {
    condition = (
      github_repository.ref.security_and_analysis[0].secret_scanning[0].status == "enabled" &&
      github_repository.ref.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    )
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public ref."
  }

  assert {
    condition     = github_repository_vulnerability_alerts.ref.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur ref."
  }
}

# Sveltia CMS commite directement sur main depuis le téléphone : pas de PR
# obligatoire, seulement une protection contre la perte d'historique.
run "protection_de_main_sans_pr" {
  command = plan

  assert {
    condition     = github_branch_protection.ref_main.pattern == "main"
    error_message = "La protection doit porter sur main."
  }

  assert {
    condition     = github_branch_protection.ref_main.repository_id == github_repository.ref.node_id
    error_message = "La protection doit viser le node_id de github_repository.ref."
  }

  assert {
    condition     = length(github_branch_protection.ref_main.required_pull_request_reviews) == 0
    error_message = "Aucune PR ne doit être exigée sur main : Sveltia CMS y commite directement."
  }

  assert {
    condition     = github_branch_protection.ref_main.allows_force_pushes == false && github_branch_protection.ref_main.allows_deletions == false
    error_message = "Ni force-push ni suppression de main."
  }
}

run "projet_cloudflare_pages" {
  command = plan

  assert {
    condition     = cloudflare_pages_project.ref.name == "ref" && cloudflare_pages_project.ref.production_branch == "main"
    error_message = "Le projet Pages doit s'appeler comme le dépôt et déployer main en production."
  }

  assert {
    condition     = cloudflare_pages_project.ref.account_id == "0123456789abcdef0123456789abcdef"
    error_message = "Le projet Pages doit être créé dans le compte CLOUDFLARE_ACCOUNT_ID de secrets.sops.yaml."
  }

  assert {
    condition = (
      cloudflare_pages_project.ref.source.type == "github" &&
      cloudflare_pages_project.ref.source.config.owner == "sylvainmetayer" &&
      cloudflare_pages_project.ref.source.config.repo_name == github_repository.ref.name &&
      cloudflare_pages_project.ref.source.config.production_branch == "main"
    )
    error_message = "Le projet Pages doit être relié au dépôt GitHub sylvainmetayer/ref, branche main."
  }

  # Sortie d'Eleventy.
  assert {
    condition     = cloudflare_pages_project.ref.build_config.build_command == "npm run build" && cloudflare_pages_project.ref.build_config.destination_dir == "_site"
    error_message = "Build Pages : npm run build, sortie dans _site (Eleventy)."
  }

  assert {
    condition     = cloudflare_pages_domain.ref.name == "ref.sylvain.dev" && cloudflare_pages_domain.ref.project_name == cloudflare_pages_project.ref.name
    error_message = "Le domaine personnalisé ref.sylvain.dev doit être attaché au projet Pages ref."
  }
}

# sylvain.dev n'est pas une zone Cloudflare : pas d'injection automatique du
# beacon, le site l'insère lui-même avec le jeton exporté.
run "web_analytics" {
  command = plan

  assert {
    condition     = cloudflare_web_analytics_site.ref.host == "ref.sylvain.dev"
    error_message = "Web Analytics doit suivre l'hôte ref.sylvain.dev."
  }

  assert {
    condition     = cloudflare_web_analytics_site.ref.auto_install == false
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
      ovh_domain_zone_record.ref.zone == "sylvain.dev" &&
      ovh_domain_zone_record.ref.subdomain == "ref" &&
      ovh_domain_zone_record.ref.fieldtype == "CNAME"
    )
    error_message = "ref.sylvain.dev doit être un CNAME explicite dans la zone OVH sylvain.dev, sinon le joker l'envoie vers Pangolin."
  }

  # Sans le point final, OVH complète la cible avec la zone :
  # ref-4ab.pages.dev.sylvain.dev.
  assert {
    condition     = ovh_domain_zone_record.ref.target == "ref-4ab.pages.dev."
    error_message = "La cible du CNAME doit être le sous-domaine pages.dev du projet, terminé par un point."
  }

  assert {
    condition     = ovh_domain_zone_record.ref.ttl == 300
    error_message = "TTL du CNAME : 300."
  }

  assert {
    condition     = output.pages_subdomain == "ref-4ab.pages.dev"
    error_message = "La sortie pages_subdomain doit être le sous-domaine du projet Pages."
  }
}

# Posée à l'apex : un nom porteur d'un CNAME (ref) ne peut porter aucun autre
# enregistrement.
run "verification_google_a_l_apex" {
  command = plan

  assert {
    condition     = length(ovh_domain_zone_record.google_site_verification) == 1
    error_message = "Avec un jeton, l'enregistrement de vérification Google doit exister."
  }

  assert {
    condition = (
      ovh_domain_zone_record.google_site_verification[0].subdomain == "" &&
      ovh_domain_zone_record.google_site_verification[0].fieldtype == "TXT" &&
      ovh_domain_zone_record.google_site_verification[0].zone == "sylvain.dev"
    )
    error_message = "La vérification Google doit être un TXT à l'apex de sylvain.dev, pas sur ref (porteur du CNAME)."
  }

  assert {
    condition = (
      startswith(ovh_domain_zone_record.google_site_verification[0].target, "\"google-site-verification=") &&
      endswith(ovh_domain_zone_record.google_site_verification[0].target, "\"")
    )
    error_message = "La valeur du TXT doit être le jeton google-site-verification=… entre guillemets."
  }
}

run "sans_verification_google" {
  command = plan

  variables {
    google_site_verification = null
  }

  assert {
    condition     = length(ovh_domain_zone_record.google_site_verification) == 0
    error_message = "google_site_verification = null ne doit poser aucun TXT."
  }
}

# Mode « All repositories » ou installation pas encore faite : rien à poser.
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
    condition     = length(github_app_installation_repository.cloudflare) == 1
    error_message = "Avec cloudflare_github_installation_id, l'app GitHub Cloudflare doit recevoir l'accès au dépôt."
  }

  assert {
    condition = (
      tostring(github_app_installation_repository.cloudflare[0].installation_id) == "12345678" &&
      github_app_installation_repository.cloudflare[0].repository == github_repository.ref.name
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
      cloudflare_pages_domain.ref.name == "parrainage.sylvain.dev" &&
      cloudflare_web_analytics_site.ref.host == "parrainage.sylvain.dev" &&
      ovh_domain_zone_record.ref.subdomain == "parrainage" &&
      github_repository.ref.homepage_url == "https://parrainage.sylvain.dev"
    )
    error_message = "Domaine Pages, Web Analytics, CNAME et page d'accueil doivent tous suivre var.subdomain."
  }
}
