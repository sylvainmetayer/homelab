# ---------------------------------------------------------------------------
# Audits de rules.tf (les quatre terraform_data à preconditions et le check
# target_health) et d'access_inventory.tf (jetons d'accès et rôles), nourris
# par les data "http" qui lisent l'API Pangolin.
#
# Chaque run négatif fait échouer UNE precondition à la fois, sur une réponse
# d'API minimale construite pour ne déclencher qu'elle : c'est ce qui prouve
# que l'audit mord, et pas seulement qu'il passe quand tout va bien.
#
# Aucun backend, aucune clé SOPS, aucun appel réseau : tous les providers sont
# simulés et chaque data source lue par la configuration est surchargée.
# ---------------------------------------------------------------------------

mock_provider "pangolin" {
  # Le provider refuse un site_id < 1 dès la validation, or un mock vaut 0.
  mock_resource "pangolin_site" {
    defaults = {
      id = 1
    }
  }
  # De même pour health_check_ids (alerts.tf).
  mock_resource "pangolin_health_check" {
    defaults = {
      id = 1
    }
  }
  # Et pour ai_provider_ids de la passerelle IA (ai_gateway.tf).
  mock_resource "pangolin_ai_provider" {
    defaults = {
      id = 1
    }
  }
}
# L'IdP passe par la clé root (pocket_id.tf) ; pocketid_client.pangolin valide
# son URL de rappel, qu'un mock tire au hasard.
mock_provider "pangolin" {
  alias = "root"
  mock_resource "pangolin_idp" {
    defaults = {
      redirect_url = "https://pangolin.example.test/auth/idp/1/oidc/callback"
    }
  }
}
mock_provider "sops" {}
mock_provider "uptimekuma" {}
mock_provider "http" {}
mock_provider "pocketid" {}

# Les pays de voyage dépendent de l'horloge du plan (plantimestamp) : sans cette
# valeur, le nombre de règles pays changerait le jour où un voyage se termine.
# Les runs qui les testent fixent la leur, avec des dates hors d'atteinte.
variables {
  state_encryption_passphrase = "tofu-test-passphrase-not-a-secret"
  travel_countries            = {}
}

# Toutes les clés lues dans secrets.tf (data.sops_file.secrets.data[...]).
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      pangolin_org_id        = "homelab"
      pangolin_url           = "https://api.pangolin.example.test"
      pangolin_api_key       = "fake-pangolin-api-key"
      UPTIMEKUMA_ENDPOINT    = "https://uptime.example.test"
      UPTIMEKUMA_USERNAME    = "admin"
      UPTIMEKUMA_PASSWORD    = "fake-uptimekuma-pass"
      home_ip                = "203.0.113.10"
      immich_pin             = "123456"
      neonova_pin            = "123456"
      ntfy_uptime_kuma_token = "fake-ntfy-uptime-kuma-token"

      pocket_id_static_api_key = "fake-pocket-id-static-api-key"
      pangolin_root_api_key    = "fake-pangolin-root-api-key"

      # Passerelle IA (ai_gateway.tf), allumée : sa clé doit exister.
      pangolin_ai_anthropic_api_key = "fake-anthropic-api-key"

      uptimekuma_telegram_bot_token = "fake-telegram-bot-token"
      uptimekuma_telegram_chat_id   = "-100123456789"
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
# (valeur simulée par défaut) ferait échouer ces deux lookups.
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
# comparerait rien. Une surcharge sans clé vise toutes les instances d'un
# for_each : un identifiant commun à toutes les règles pays PASS, un autre aux
# DROP.
override_resource {
  target = pangolin_resource_rule.allow_countries
  values = { id = 1010 }
}

override_resource {
  target = pangolin_resource_rule.block_country
  values = { id = 1099 }
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

override_resource {
  target = pangolin_resource_rule.immich_kiosk_home_ip
  values = { id = 2099 }
}

# Un identifiant commun à toutes les instances, comme pour les règles pays.
override_resource {
  target = pangolin_resource_rule.backslash_guard
  values = { id = 2008 }
}

# Un identifiant commun aux ouvertures par chemin, et un identifiant propre à
# cinq d'entre elles, anciennes règles autonomes passées dans
# local.path_bypasses : la réponse simulée de l'API les porte, si bien que
# l'une d'elles sortie de la configuration ferait échouer l'inventaire.
override_resource {
  target = pangolin_resource_rule.path_bypass
  values = { id = 2011 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass["Flip Planning /mcp/*"]
  values = { id = 2001 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass["Demo Planning /mcp/*"]
  values = { id = 2002 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass["Demo Planning KC /auth/*"]
  values = { id = 2003 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass["Karakeep /public/lists/*"]
  values = { id = 2007 }
}

override_resource {
  target = pangolin_resource_rule.path_bypass["TREK /oauth/token"]
  values = { id = 2010 }
}

override_resource {
  target = pangolin_resource_rule.trek_mcp
  values = { id = 2009 }
}

override_resource {
  target = pangolin_resource_rule.beszel_agent_connect
  values = { id = 2012 }
}

override_resource {
  target = pangolin_resource_rule.victoria_logs_insert
  values = { id = 2013 }
}

override_resource {
  target = pangolin_resource_rule.rss_opml
  values = { id = 2014 }
}

override_resource {
  target = pangolin_resource_access_token.rss_site_build
  values = { id = "tok-rss-build", token = "jeton-rss-build" }
}

# Identifiants des cibles, des jetons d'accès et des rôles, lus par les audits
# target_inventory (rules.tf) et access_inventory (access_inventory.tf) : sans
# valeur fixe, le mock leur donne une valeur que les réponses simulées
# ci-dessous ne peuvent pas porter. Un identifiant commun à toutes les cibles,
# et un propre à l'une d'elles : la réponse simulée porte les deux.
override_resource {
  target = pangolin_target.website
  values = { id = 101 }
}

override_resource {
  target = pangolin_target.website["flip_planning_mailpit"]
  values = { id = 102 }
}

override_resource {
  target = pangolin_resource_access_token.healthcheck
  values = { id = "tok-healthcheck", token = "jeton-healthcheck" }
}

override_resource {
  target = pangolin_resource_access_token.karakeep_clients
  values = { id = "tok-karakeep", token = "jeton-karakeep" }
}

override_resource {
  target = pangolin_resource_access_token.immich_clients
  values = { id = "tok-immich", token = "jeton-immich" }
}

override_resource {
  target = pangolin_resource_access_token.papra_clients
  values = { id = "tok-papra", token = "jeton-papra" }
}

override_resource {
  target = pangolin_role.apps
  values = { id = 3001 }
}

override_resource {
  target = pangolin_resource_access_token.beszel_agents
  values = { id = "tok-beszel-agent", token = "jeton-beszel-agent" }
}

override_resource {
  target = pangolin_resource_access_token.trek_mcp_clients
  values = { id = "tok-trek-mcp", token = "jeton-trek-mcp" }
}

override_resource {
  target = pangolin_resource_access_token.log_agents
  values = { id = "tok-log-agent", token = "jeton-log-agent" }
}

override_resource {
  target = pangolin_role.jellyfin
  values = { id = 90 }
}

# --- Réponses réalistes de l'API Pangolin (cas nominal) ---------------------

# GET /v1/org/{org}/access-tokens?limit=1000 : un jeton par ressource de
# jetons déclarée (les identifiants fixés plus haut). Comme en vrai,
# `pagination.total` ne compte pas la liste.
override_data {
  target = data.http.pangolin_access_tokens
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"accessTokens": [
        {"accessTokenId": "tok-healthcheck", "title": "Healthcheck", "resourceName": "Flip Planning", "expiresAt": null},
        {"accessTokenId": "tok-beszel-agent", "title": "Beszel agent", "resourceName": "Beszel", "expiresAt": null},
        {"accessTokenId": "tok-karakeep", "title": "Karakeep", "resourceName": "Karakeep", "expiresAt": null},
        {"accessTokenId": "tok-papra", "title": "Papra mobile", "resourceName": "Papra", "expiresAt": null},
        {"accessTokenId": "tok-trek-mcp", "title": "TREK MCP", "resourceName": "TREK", "expiresAt": null},
        {"accessTokenId": "tok-log-agent", "title": "Log agent", "resourceName": "VictoriaLogs", "expiresAt": null}
      ], "pagination": {"total": 2, "limit": 1000, "offset": 0}},
      "success": true, "error": false, "message": "Access tokens retrieved successfully", "status": 200}
    EOT
  }
}

# GET /v1/org/{org}/roles?pageSize=1000 : les deux rôles intégrés, celui
# commun à pangolin_role.apps et celui de Jellyfin.
override_data {
  target = data.http.pangolin_roles
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"roles": [
        {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true, "allowSsh": true},
        {"roleId": 2, "name": "Member", "description": "", "isAdmin": null, "allowSsh": false},
        {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null, "allowSsh": false},
        {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null, "allowSsh": false}
      ], "pagination": {"total": 4, "page": 1, "pageSize": 1000}},
      "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
    EOT
  }
}


# GET /v1/org/{org}/resources?pageSize=1000 : les ressources gérées, et un
# reste désactivé créé dans l'UI, que l'audit doit ignorer puisqu'il n'est pas
# servi.
override_data {
  target = data.http.pangolin_resources
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"resources": [
        {"resourceId": 65, "niceId": "beszel", "name": "Beszel", "fullDomain": "monitoring.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true},
        {"resourceId": 60, "niceId": "dawarich", "name": "Dawarich", "fullDomain": "tracks.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 81, "niceId": "demo-planning", "name": "Demo Planning", "fullDomain": "demo-planning.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 82, "niceId": "demo-planning-kc", "name": "Demo Planning KC", "fullDomain": "demo-planning-kc.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 80, "niceId": "flip-planning", "name": "Flip Planning", "fullDomain": "flip-planning.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 23, "niceId": "immich-swipe", "name": "Immich Swipe", "fullDomain": "swipe-photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 62, "niceId": "karakeep", "name": "Karakeep", "fullDomain": "keep.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 31, "niceId": "monica", "name": "Monica CRM", "fullDomain": "crm.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 11, "niceId": "nextcloud", "name": "nextcloud", "fullDomain": "sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 32, "niceId": "rss", "name": "RSS", "fullDomain": "rss.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 61, "niceId": "trek", "name": "TREK", "fullDomain": "travels.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 33, "niceId": "wiki", "name": "Wiki (Bookstack)", "fullDomain": "wiki.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 63, "niceId": "wishlist", "name": "Wishlist", "fullDomain": "cadeaux.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 90, "niceId": "test-manuel", "name": "Test manuel", "fullDomain": "test.sylvain.cloud", "sso": true, "enabled": false}
      ], "pagination": {"total": 16, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
    EOT
  }
}

# GET /v1/resource/{id}/targets, même réponse pour chaque ressource gérée (une
# surcharge vise toutes les instances du for_each). Une cible sondée et saine,
# et une cible sans sonde dont scheme et port sont NULL, comme NAS en vrai :
# l'audit ne doit rien reprocher à cette dernière.
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
# règles spécifiques (2001 à 2013) : si l'une d'elles disparaît de
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
        {"ruleId": 2008, "action": "DROP", "match": "PATH", "value": "/*/*%5C*/*", "priority": 1, "enabled": true},
        {"ruleId": 2007, "action": "ACCEPT", "match": "PATH", "value": "/public/lists/*", "priority": 2, "enabled": true},
        {"ruleId": 2009, "action": "PASS", "match": "PATH", "value": "/mcp", "priority": 3, "enabled": true},
        {"ruleId": 2012, "action": "PASS", "match": "PATH", "value": "/api/beszel/agent-connect", "priority": 3, "enabled": true},
        {"ruleId": 2013, "action": "PASS", "match": "PATH", "value": "/insert/jsonline", "priority": 3, "enabled": true},
        {"ruleId": 2010, "action": "ACCEPT", "match": "PATH", "value": "/oauth/token", "priority": 2, "enabled": true},
        {"ruleId": 2011, "action": "ACCEPT", "match": "PATH", "value": "/share/*", "priority": 4, "enabled": true},
        {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
      ], "pagination": {"total": 15, "pageSize": 1000, "page": 1}},
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
    condition     = terraform_data.geo_rule_coverage.output == length(local.managed_resources)
    error_message = "geo_rule_coverage doit porter sur toutes les ressources gérées."
  }

  assert {
    condition     = terraform_data.target_probe_config.output == length(local.managed_resources) * 2
    error_message = "target_probe_config doit lire les cibles de toutes les ressources gérées (2 cibles chacune dans la réponse simulée)."
  }

  assert {
    condition     = terraform_data.rule_inventory.output == length(local.managed_resources) * 15
    error_message = "rule_inventory doit lire les règles de toutes les ressources couvertes (15 règles chacune dans la réponse simulée)."
  }

  assert {
    condition     = terraform_data.target_inventory.output == length(local.managed_resources) * 2
    error_message = "target_inventory doit comparer les cibles de toutes les ressources gérées (2 cibles chacune dans la réponse simulée)."
  }

  # 6 jetons et 4 rôles dans les réponses simulées, aucune exception périmée.
  assert {
    condition     = terraform_data.access_inventory.output == 10 && length(local.stale_inventory_exceptions) == 0
    error_message = "access_inventory doit lire les 6 jetons et les 4 rôles de la réponse simulée, et toutes les exceptions y être vivantes."
  }
}

# ---------------------------------------------------------------------------
# geo_rule_coverage
# ---------------------------------------------------------------------------

# Le cas qui a duré des mois : une application activée dans Pangolin sans
# entrée dans local.managed_resources est publique
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
          {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true},
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
# 22 ressources mais n'en liste que 2 (toutes deux connues).
run "truncated_resource_list_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_resources
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"resources": [
          {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true}
        ], "pagination": {"total": 22, "pageSize": 20, "page": 1}},
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
          {"targetId": 101, "ip": "grampsweb", "method": "http", "port": 5000, "enabled": true,
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

  # Wishlist désactivée dans Pangolin (comme Gramps l'était, arrêtée exprès) :
  # sa sonde en échec est attendue et ne doit pas s'ajouter à l'avertissement.
  override_data {
    target = data.http.pangolin_resources
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"resources": [
          {"resourceId": 80, "niceId": "flip-planning", "name": "Flip Planning", "fullDomain": "flip-planning.sylvain.cloud", "sso": true, "enabled": true},
          {"resourceId": 63, "niceId": "wishlist", "name": "Wishlist", "fullDomain": "cadeaux.sylvain.cloud", "sso": true, "enabled": false}
        ], "pagination": {"total": 2, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Resources retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    check.target_health,
  ]

  assert {
    condition = (
      length(local.unhealthy_targets) > 0
      && !anytrue([for label in local.unhealthy_targets : startswith(label, "Wishlist#")])
    )
    error_message = "Une cible en échec doit lever l'avertissement target_health, sauf celle d'une ressource désactivée (Wishlist ici)."
  }
}

# ---------------------------------------------------------------------------
# target_inventory
# ---------------------------------------------------------------------------

# Une cible ajoutée à la main dans l'UI à une ressource gérée : Traefik lui
# envoie sa part des requêtes, et aucune pangolin_target ne la porte.
run "hand_made_target_fails_plan" {
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
           "hcPort": 8080, "hcPath": "/", "hcHealth": "healthy"},
          {"targetId": 4343, "ip": "192.168.1.50", "method": "http", "port": 80, "enabled": true,
           "path": null, "pathMatchType": null, "priority": 100,
           "hcEnabled": false, "hcScheme": null, "hcMode": null, "hcHostname": null,
           "hcPort": null, "hcPath": null, "hcHealth": "unknown"}
        ], "pagination": {"total": 2, "pageSize": 1000, "page": 1}},
        "success": true, "error": false, "message": "Targets retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.target_inventory,
  ]

  assert {
    condition     = length(local.undeclared_targets) == length(local.managed_resources) && alltrue([for label in local.undeclared_targets : strcontains(label, "#4343")])
    error_message = "Seule la cible faite main (4343) doit être signalée, sur chaque ressource gérée."
  }
}

# Liste de cibles tronquée : la cible faite main pourrait être hors de la page.
run "truncated_target_list_fails_plan" {
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
           "hcPort": 8080, "hcPath": "/", "hcHealth": "healthy"}
        ], "pagination": {"total": 3, "pageSize": 1, "page": 1}},
        "success": true, "error": false, "message": "Targets retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.target_inventory,
  ]
}

# ---------------------------------------------------------------------------
# access_inventory (access_inventory.tf)
# ---------------------------------------------------------------------------

# Un jeton fait main hors des exceptions, sans titre (coalesce ne doit pas
# faire planter le plan) : un accès permanent derrière le mur SSO que rien
# dans le dépôt ne mentionne.
run "hand_made_access_token_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_access_tokens
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"accessTokens": [
          {"accessTokenId": "tok-healthcheck", "title": "Healthcheck", "resourceName": "Flip Planning", "expiresAt": null},
          {"accessTokenId": "zz99main", "title": null, "resourceName": "Immich", "expiresAt": null}
        ], "pagination": {"total": 4, "limit": 1000, "offset": 0}},
        "success": true, "error": false, "message": "Access tokens retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]

  assert {
    condition     = length(local.undeclared_access_tokens) == 1 && strcontains(local.undeclared_access_tokens[0], "zz99main")
    error_message = "Seul le jeton fait main hors exception (zz99main) doit être signalé."
  }
}

# Un rôle fait main hors des exceptions.
run "hand_made_role_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_roles
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"roles": [
          {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true, "allowSsh": true},
          {"roleId": 2, "name": "Member", "description": "", "isAdmin": null, "allowSsh": false},
          {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null, "allowSsh": false},
          {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null, "allowSsh": false},
          {"roleId": 77, "name": "invités", "description": "", "isAdmin": null, "allowSsh": false}
        ], "pagination": {"total": 5, "page": 1, "pageSize": 1000}},
        "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]

  assert {
    condition     = local.undeclared_roles == ["77 (invités)"]
    error_message = "Seul le rôle fait main hors exception (77) doit être signalé."
  }
}

# Un rôle d'app passé en SSH dans l'UI : le plan ne le voit pas (le provider garde
# le state), seul l'audit le signale. Admin, hors de cette configuration, garde
# son SSH.
run "app_role_with_ssh_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_roles
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"roles": [
          {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true, "allowSsh": true},
          {"roleId": 2, "name": "Member", "description": "", "isAdmin": null, "allowSsh": false},
          {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null, "allowSsh": true},
          {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null, "allowSsh": false}
        ], "pagination": {"total": 4, "page": 1, "pageSize": 1000}},
        "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]

  assert {
    condition     = local.ssh_enabled_roles == ["3001 (immich)"]
    error_message = "Seul le rôle d'app ouvert au SSH (3001) doit être signalé."
  }
}

# Le champ disparaît de la réponse, comme à la lecture d'un rôle depuis Pangolin
# 1.19 : l'audit arrête le plan au lieu de devenir aveugle.
run "role_list_without_allow_ssh_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_roles
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"roles": [
          {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true},
          {"roleId": 2, "name": "Member", "description": "", "isAdmin": null},
          {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null},
          {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null}
        ], "pagination": {"total": 4, "page": 1, "pageSize": 1000}},
        "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]

  assert {
    condition     = local.ssh_enabled_roles == ["3001 (immich)", "90 (jellyfin)"]
    error_message = "Sans le champ allowSsh, chaque rôle d'app compte comme ouvert."
  }
}

# Liste de rôles tronquée (la valeur par défaut de l'API est 20 par page).
run "truncated_role_list_fails_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_roles
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"roles": [
          {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true, "allowSsh": true}
        ], "pagination": {"total": 23, "page": 1, "pageSize": 20}},
        "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]
}

# Clé API privée de listAccessTokens : la liste ne se décode pas, et l'audit le
# dit au lieu de passer pour « aucun jeton ».
run "unreadable_access_tokens_fail_plan" {
  command = plan

  override_data {
    target = data.http.pangolin_access_tokens
    values = {
      status_code   = 403
      response_body = <<-EOT
        {"data": null, "success": false, "error": true, "message": "Key does not have permission perform this action", "status": 403}
      EOT
    }
  }

  expect_failures = [
    terraform_data.access_inventory,
  ]
}

# Le rôle d'une exception disparu de Pangolin (ici Member) : l'exception est
# périmée, un avertissement le dit sans bloquer le plan.
run "stale_inventory_exception_only_warns" {
  command = plan

  override_data {
    target = data.http.pangolin_roles
    values = {
      status_code   = 200
      response_body = <<-EOT
        {"data": {"roles": [
          {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true, "allowSsh": true},
          {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null, "allowSsh": false},
          {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null, "allowSsh": false}
        ], "pagination": {"total": 3, "page": 1, "pageSize": 1000}},
        "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
      EOT
    }
  }

  expect_failures = [
    check.inventory_exceptions_stale,
  ]

  assert {
    condition     = tolist(local.stale_inventory_exceptions) == tolist(["role 2"])
    error_message = "Seule l'exception du rôle disparu (2) doit être signalée."
  }
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
