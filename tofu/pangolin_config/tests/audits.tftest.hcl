# ---------------------------------------------------------------------------
# Audits de rules.tf : les trois terraform_data à preconditions et le check
# target_health, nourris par les data "http" qui lisent l'API Pangolin.
#
# Chaque run négatif fait échouer UNE precondition à la fois, sur une réponse
# d'API minimale construite pour ne déclencher qu'elle : c'est ce qui prouve
# que l'audit mord, et pas seulement qu'il passe quand tout va bien.
#
# Aucun backend, aucune clé SOPS, aucun appel réseau : tous les providers sont
# simulés et chaque data source lue par la configuration est surchargée.
# ---------------------------------------------------------------------------

mock_provider "pangolin" {}
mock_provider "sops" {}
mock_provider "uptimekuma" {}
mock_provider "http" {}
mock_provider "aws" {}

# Les pays de voyage dépendent de l'horloge du plan (plantimestamp) : sans cette
# valeur, le nombre de règles pays changerait le jour où un voyage se termine.
# Les runs qui les testent fixent la leur, avec des dates hors d'atteinte.
variables {
  travel_countries = {}
}

# Toutes les clés lues dans secrets.tf (data.sops_file.secrets.data[...]).
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      pangolin_org_id       = "homelab"
      pangolin_url          = "https://api.pangolin.example.test"
      pangolin_api_key      = "fake-pangolin-api-key"
      AWS_ACCESS_KEY_ID     = "fake-access-key"
      AWS_SECRET_ACCESS_KEY = "fake-secret-key"
      smtp_user             = "alertes@example.test"
      smtp_pass             = "fake-smtp-pass"
      le_email              = "admin@example.test"
      UPTIMEKUMA_ENDPOINT   = "https://uptime.example.test"
      UPTIMEKUMA_USERNAME   = "admin"
      UPTIMEKUMA_PASSWORD   = "fake-uptimekuma-pass"
      home_ip               = "203.0.113.10"
      immich_pin            = "123456"
    }
  }
}

# Sortie de tofu/pangolin lue pour flip.internal (remote_state.tf).
override_data {
  target = data.terraform_remote_state.pangolin
  values = {
    outputs = {
      flip_private_ip = "10.0.1.10"
    }
  }
}

# local.domain_ids indexe "sylvain.cloud" et "sylvain.dev" : une liste vide
# (valeur simulée par défaut) ferait échouer domains[0] et ces deux lookups.
# Tous les champs de l'objet imbriqué sont fournis, sans quoi la valeur ne se
# convertit pas vers le type du schéma.
override_data {
  target = data.pangolin_domains.all
  values = {
    domains = [
      {
        domain_id            = "dom-cloud"
        base_domain          = "sylvain.cloud"
        type                 = "ns"
        verified             = true
        failed               = false
        tries                = 0
        config_managed       = false
        prefer_wildcard_cert = false
        cert_resolver        = "letsencrypt"
        custom_cert_resolver = ""
        error_message        = ""
      },
      {
        domain_id            = "dom-dev"
        base_domain          = "sylvain.dev"
        type                 = "ns"
        verified             = true
        failed               = false
        tries                = 0
        config_managed       = false
        prefer_wildcard_cert = false
        cert_resolver        = "letsencrypt"
        custom_cert_resolver = ""
        error_message        = ""
      },
    ]
  }
}

# Les identifiants des règles sont des attributs calculés : sans valeur fixe,
# le mock leur donne à toutes la même valeur et l'audit d'inventaire ne
# comparerait rien. Une instance for_each ne peut pas être surchargée seule,
# d'où un identifiant commun à toutes les règles pays PASS, et un autre aux DROP.
override_resource {
  target = pangolin_resource_rule.allow_countries
  values = { id = 1010 }
}

override_resource {
  target = pangolin_resource_rule.block_country
  values = { id = 1099 }
}

override_resource {
  target = pangolin_resource_rule.flip_planning_mcp
  values = { id = 2001 }
}

override_resource {
  target = pangolin_resource_rule.demo_planning_mcp
  values = { id = 2002 }
}

override_resource {
  target = pangolin_resource_rule.demo_planning_kc_keycloak
  values = { id = 2003 }
}

override_resource {
  target = pangolin_resource_rule.immich_home_ip
  values = { id = 2004 }
}

override_resource {
  target = pangolin_resource_rule.dawarich_home_ip
  values = { id = 2005 }
}

override_resource {
  target = pangolin_resource_rule.trek_home_ip
  values = { id = 2006 }
}

# Une instance for_each ne peut pas être surchargée seule : identifiant commun
# aux cinq chemins publics de Karakeep.
override_resource {
  target = pangolin_resource_rule.karakeep_public
  values = { id = 2007 }
}

# Un identifiant commun à toutes les instances, comme pour les autres for_each.
override_resource {
  target = pangolin_resource_rule.backslash_guard
  values = { id = 2008 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass
  values = { id = 2011 }
}

override_resource {
  target = pangolin_resource_rule.trek_mcp
  values = { id = 2009 }
}

# Même contrainte que karakeep_public : un identifiant commun aux instances.
override_resource {
  target = pangolin_resource_rule.trek_mcp_oauth
  values = { id = 2010 }
}

# --- Réponses réalistes de l'API Pangolin (cas nominal) ---------------------

# GET /v1/org/{org}/resources?pageSize=1000 : les 23 ressources gérées, la
# ressource faite à la main "SSH PI" (épinglée dans local.unmanaged_resources)
# et un reste désactivé créé dans l'UI, que l'audit doit ignorer puisqu'il
# n'est pas servi.
override_data {
  target = data.http.pangolin_resources
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"resources": [
        {"resourceId": 15, "niceId": "bbox", "name": "BBOX", "fullDomain": "bbox.sylvain.cloud", "sso": true, "enabled": false},
        {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true},
        {"resourceId": 2, "niceId": "dashboard", "name": "Dashboard Traefik", "fullDomain": "dashboard.sylvain.cloud", "sso": true, "enabled": false},
        {"resourceId": 60, "niceId": "dawarich", "name": "Dawarich", "fullDomain": "tracks.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 81, "niceId": "demo-planning", "name": "Demo Planning", "fullDomain": "demo-planning.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 82, "niceId": "demo-planning-kc", "name": "Demo Planning KC", "fullDomain": "demo-planning-kc.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 22, "niceId": "echo", "name": "Echo", "fullDomain": "echo.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 80, "niceId": "flip-planning", "name": "Flip Planning", "fullDomain": "flip-planning.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 55, "niceId": "gramps", "name": "Gramps", "fullDomain": "trees.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 23, "niceId": "immich-swipe", "name": "Immich Swipe", "fullDomain": "swipe-photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 62, "niceId": "karakeep", "name": "Karakeep", "fullDomain": "keep.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 30, "niceId": "meerkat-crm", "name": "Meerkat CRM", "fullDomain": "crm.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 31, "niceId": "monica", "name": "Monica CRM", "fullDomain": "crm.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 75, "niceId": "nas", "name": "NAS", "fullDomain": "nas.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 11, "niceId": "nextcloud", "name": "nextcloud", "fullDomain": "sylvain.cloud", "sso": false, "enabled": true},
        {"resourceId": 40, "niceId": "paperless", "name": "Paperless-ngx", "fullDomain": "papiers.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 4, "niceId": "proxmox", "name": "Proxmox", "fullDomain": "proxmox.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 32, "niceId": "rss", "name": "RSS", "fullDomain": "rss.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 56, "niceId": "scanopy", "name": "Scanopy", "fullDomain": "scan.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 41, "niceId": "searxng", "name": "SearXNG", "fullDomain": "search.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 38, "niceId": "ssh-pi", "name": "SSH PI", "fullDomain": "remote.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 61, "niceId": "trek", "name": "TREK", "fullDomain": "travels.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 33, "niceId": "wiki", "name": "Wiki (Bookstack)", "fullDomain": "wiki.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 90, "niceId": "test-manuel", "name": "Test manuel", "fullDomain": "test.sylvain.cloud", "sso": true, "enabled": false}
      ], "pagination": {"total": 25, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
    EOT
  }
}

# GET /v1/resource/{id}/targets, même réponse pour chaque ressource gérée (une
# surcharge vise toutes les instances du for_each). Une cible sondée et saine,
# et une cible sans sonde dont scheme et port sont NULL, comme NAS ou le
# dashboard Traefik en vrai : l'audit ne doit rien reprocher à cette dernière.
override_data {
  target = data.http.pangolin_targets
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"targets": [
        {"targetId": 101, "ip": "flip-planning", "method": "http", "port": 8080, "enabled": true,
         "path": "/", "pathMatchType": "prefix", "priority": 1,
         "hcEnabled": true, "hcScheme": "http", "hcMode": "http", "hcHostname": "flip-planning",
         "hcPort": 8080, "hcPath": "/", "hcHealth": "healthy"},
        {"targetId": 102, "ip": "192.168.1.137", "method": "http", "port": 9999, "enabled": true,
         "path": null, "pathMatchType": null, "priority": 100,
         "hcEnabled": false, "hcScheme": null, "hcMode": null, "hcHostname": null,
         "hcPort": null, "hcPath": null, "hcHealth": "unknown"}
      ], "pagination": {"total": 2, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Targets retrieved successfully", "status": 200}
    EOT
  }
}

# GET /v1/resource/{id}/rules, même réponse pour chaque ressource couverte.
# Elle contient les identifiants de TOUTES les règles déclarées, y compris les
# règles spécifiques (2001 à 2011) : si l'une d'elles disparaît de
# local.declared_extra_rules, le run nominal échoue.
override_data {
  target = data.http.pangolin_rules
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"rules": [
        {"ruleId": 2001, "action": "ACCEPT", "match": "PATH", "value": "/mcp/*", "priority": 2, "enabled": true},
        {"ruleId": 2002, "action": "ACCEPT", "match": "PATH", "value": "/mcp/*", "priority": 2, "enabled": true},
        {"ruleId": 2003, "action": "ACCEPT", "match": "PATH", "value": "/auth/*", "priority": 2, "enabled": true},
        {"ruleId": 1010, "action": "PASS", "match": "COUNTRY", "value": "FR", "priority": 10, "enabled": true},
        {"ruleId": 2004, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 9, "enabled": true},
        {"ruleId": 2005, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 9, "enabled": true},
        {"ruleId": 2006, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 9, "enabled": true},
        {"ruleId": 2007, "action": "ACCEPT", "match": "PATH", "value": "/public/lists/*", "priority": 2, "enabled": true},
        {"ruleId": 2008, "action": "DROP", "match": "PATH", "value": "/*/*%5C*/*", "priority": 1, "enabled": true},
        {"ruleId": 2009, "action": "PASS", "match": "PATH", "value": "/mcp", "priority": 3, "enabled": true},
        {"ruleId": 2010, "action": "ACCEPT", "match": "PATH", "value": "/oauth/token", "priority": 2, "enabled": true},
        {"ruleId": 2011, "action": "ACCEPT", "match": "PATH", "value": "/share/*", "priority": 4, "enabled": true},
        {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
      ], "pagination": {"total": 13, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Rules retrieved successfully", "status": 200}
    EOT
  }
}

# ---------------------------------------------------------------------------
# Cas nominal
# ---------------------------------------------------------------------------

# En apply, toutes les valeurs calculées sont connues : les trois preconditions
# et le check sont évalués quoi qu'il arrive au plan. Les `input` prouvent en
# plus que les audits ont VU des données pour chaque ressource, au lieu de
# passer sur une liste vide.
run "audits_pass_on_realistic_api_responses" {
  command = apply

  assert {
    condition     = terraform_data.geo_rule_coverage.output == 24
    error_message = "geo_rule_coverage doit porter sur les 23 ressources gérées plus SSH PI."
  }

  assert {
    condition     = terraform_data.target_probe_config.output == 23 * 2
    error_message = "target_probe_config doit lire les cibles des 23 ressources gérées (2 cibles chacune dans la réponse simulée)."
  }

  assert {
    condition     = terraform_data.rule_inventory.output == 24 * 13
    error_message = "rule_inventory doit lire les règles des 24 ressources couvertes (13 règles chacune dans la réponse simulée)."
  }
}

# ---------------------------------------------------------------------------
# geo_rule_coverage
# ---------------------------------------------------------------------------

# Le cas qui a duré des mois : une application activée dans Pangolin sans
# entrée dans local.managed_resources (ni unmanaged_resources) est publique
# sans aucun filtrage pays. Le plan doit s'arrêter.
run "enabled_resource_missing_from_managed_resources_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_resources
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"resources": [
          {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 38, "niceId": "ssh-pi", "name": "SSH PI", "fullDomain": "remote.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 95, "niceId": "nouvelle-app", "name": "Nouvelle App", "fullDomain": "nouvelle.sylvain.cloud", "sso": true, "enabled": true}
        ], "pagination": {"total": 3, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.geo_rule_coverage,
  ]
}

# Une page tronquée rendrait le contrôle de couverture aveugle : la réponse dit
# 24 ressources mais n'en liste que 2 (toutes deux connues).
run "truncated_resource_list_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_resources
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"resources": [
          {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 38, "niceId": "ssh-pi", "name": "SSH PI", "fullDomain": "remote.sylvain.cloud", "sso": true, "enabled": true}
        ], "pagination": {"total": 24, "pageSize": 20, "page": 1}},
        "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.geo_rule_coverage,
  ]
}

# "SSH PI" est épinglée par identifiant dans local.unmanaged_resources : si elle
# a été supprimée (ou renommée) dans l'UI, l'épingle pend et le plan s'arrête.
run "dangling_unmanaged_pin_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_resources
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"resources": [
          {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true}
        ], "pagination": {"total": 2, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.geo_rule_coverage,
  ]
}

# ---------------------------------------------------------------------------
# target_probe_config et check.target_health
# ---------------------------------------------------------------------------

# L'état exact de gramps et scanopy pendant leur panne : sonde activée mais
# hcScheme/hcPort NULL, donc jamais saine et retirée du load balancer. La
# precondition bloque, et le check signale la cible malade.
run "enabled_probe_without_scheme_or_port_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_targets
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"targets": [
          {"targetId": 57, "ip": "grampsweb", "method": "http", "port": 5000, "enabled": true,
           "path": null, "pathMatchType": null, "priority": 100,
           "hcEnabled": true, "hcScheme": null, "hcMode": "http", "hcHostname": "grampsweb",
           "hcPort": null, "hcPath": "/", "hcHealth": "unhealthy"}
        ], "pagination": {"total": 1, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Targets retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.target_probe_config,
    check.target_health,
  ]
}

# Une réponse qui ne se décode pas en liste de cibles (ici un 401) est signalée,
# pas aplatie en "aucune cible" : un audit qui ne voit rien doit arrêter le plan.
run "unreadable_targets_response_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_targets
    values = {
      status_code   = 401
      response_body = <<-EOT
        {"data": null, "success": false, "error": true, "message": "Unauthorized", "status": 401}
      EOT
    }
  }

  expect_failures = [
    terraform_data.target_probe_config,
  ]
}

# La santé est une propriété d'exécution : une cible correctement configurée
# mais actuellement en panne lève le check (avertissement) sans bloquer le plan.
# Si target_health devenait une precondition, ce run échouerait.
run "unhealthy_target_only_warns" {
  command = plan

  override_data {
    target = data.http.pangolin_targets
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"targets": [
          {"targetId": 101, "ip": "flip-planning", "method": "http", "port": 8080, "enabled": true,
           "path": "/", "pathMatchType": "prefix", "priority": 1,
           "hcEnabled": true, "hcScheme": "http", "hcMode": "http", "hcHostname": "flip-planning",
           "hcPort": 8080, "hcPath": "/", "hcHealth": "unhealthy"}
        ], "pagination": {"total": 1, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Targets retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    check.target_health,
  ]
}

# ---------------------------------------------------------------------------
# rule_inventory
# ---------------------------------------------------------------------------

# Une règle ajoutée à la main dans l'UI (comme l'ACCEPT MCP qui n'existait que
# dans Pangolin, ou les doublons de Proxmox) : son identifiant n'est ni dans les
# boucles pays ni dans local.declared_extra_rules.
run "hand_made_rule_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_rules
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"rules": [
          {"ruleId": 1010, "action": "PASS", "match": "COUNTRY", "value": "FR", "priority": 10, "enabled": true},
          {"ruleId": 4242, "action": "ACCEPT", "match": "CIDR", "value": "160.79.104.0/21", "priority": 1, "enabled": true},
          {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
        ], "pagination": {"total": 3, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Rules retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.rule_inventory,
  ]
}

# Liste de règles tronquée : l'audit ne verrait pas les règles manquantes.
run "truncated_rule_list_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_rules
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"rules": [
          {"ruleId": 1010, "action": "PASS", "match": "COUNTRY", "value": "FR", "priority": 10, "enabled": true},
          {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
        ], "pagination": {"total": 13, "pageSize": 2, "page": 1}},
        "success": true, "error": false, "message": "Rules retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.rule_inventory,
  ]
}

# Une erreur serveur renvoyée en HTML : rien ne se décode, et l'audit le dit.
run "unreadable_rules_response_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_rules
    values = {
      status_code   = 500
      response_body = <<-EOT
        <html><body><h1>500 Internal Server Error</h1></body></html>
      EOT
    }
  }

  expect_failures = [
    terraform_data.rule_inventory,
  ]
}
