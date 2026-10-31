# ---------------------------------------------------------------------------
# Invariants de la configuration Pangolin / Uptime Kuma : routage des cibles,
# disposition des règles pays, moniteurs, sorties lues par Ansible et
# séparation production / démo de Flip Planning.
#
# Les runs `plan` n'assertent que des valeurs issues de la configuration (ou de
# data sources surchargées), connues au plan. Les runs `apply` couvrent ce qui
# dépend d'attributs calculés (identifiants, jetons, FQDN), fixés ci-dessous par
# des override_resource pour être à la fois connus et distincts : le mock donne
# sinon la même valeur à toutes les ressources d'un même type, et une égalité
# d'identifiants ne prouverait rien.
#
# Aucun backend, aucune clé SOPS, aucun appel réseau.
# ---------------------------------------------------------------------------

mock_provider "pangolin" {}
mock_provider "sops" {}
mock_provider "uptimekuma" {}
mock_provider "http" {}

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
      ntfy_uptime_kuma_token = "fake-ntfy-uptime-kuma-token"

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

# Un identifiant commun à toutes les instances, comme pour les règles pays.
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

override_resource {
  target = pangolin_resource_rule.beszel_agent_connect
  values = { id = 2012 }
}

override_resource {
  target = pangolin_resource_rule.victoria_logs_insert
  values = { id = 2013 }
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
  target = pangolin_resource_access_token.papra_clients
  values = { id = "tok-papra", token = "jeton-papra" }
}

override_resource {
  target = pangolin_role.apps
  values = { id = 3001 }
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
        {"accessTokenId": "tok-flip-planning", "title": "Healthcheck Flip Planning", "resourceName": "Flip Planning", "expiresAt": null},
        {"accessTokenId": "tok-demo-planning", "title": "Healthcheck Demo Planning", "resourceName": "Demo Planning", "expiresAt": null}
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
        {"roleId": 1, "name": "Admin", "description": "", "isAdmin": true},
        {"roleId": 2, "name": "Member", "description": "", "isAdmin": null},
        {"roleId": 3001, "name": "immich", "description": "", "isAdmin": null},
        {"roleId": 90, "name": "jellyfin", "description": "", "isAdmin": null}
      ], "pagination": {"total": 4, "page": 1, "pageSize": 1000}},
      "success": true, "error": false, "message": "Roles retrieved successfully", "status": 200}
    EOT
  }
}


# GET /v1/org/{org}/resources?pageSize=1000 : les 17 ressources gérées, et un
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
        {"resourceId": 40, "niceId": "paperless", "name": "Paperless-ngx", "fullDomain": "papiers.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 83, "niceId": "promptoramix", "name": "Promptoramix", "fullDomain": "promptoramix.sylvain.cloud", "sso": false, "enabled": true},
        {"resourceId": 32, "niceId": "rss", "name": "RSS", "fullDomain": "rss.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 61, "niceId": "trek", "name": "TREK", "fullDomain": "travels.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 33, "niceId": "wiki", "name": "Wiki (Bookstack)", "fullDomain": "wiki.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 63, "niceId": "wishlist", "name": "Wishlist", "fullDomain": "cadeaux.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 90, "niceId": "test-manuel", "name": "Test manuel", "fullDomain": "test.sylvain.cloud", "sso": true, "enabled": false}
      ], "pagination": {"total": 18, "pageSize": 1000, "page": 1}},
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
# règles spécifiques (2004 à 2012) : si l'une d'elles disparaît de
# local.declared_extra_rules, le run nominal échoue.
override_data {
  target = data.http.pangolin_rules
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"rules": [
        {"ruleId": 1010, "action": "PASS", "match": "COUNTRY", "value": "FR", "priority": 10, "enabled": true},
        {"ruleId": 2004, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 2005, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 2006, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 2008, "action": "DROP", "match": "PATH", "value": "/*/*%5C*/*", "priority": 1, "enabled": true},
        {"ruleId": 2009, "action": "PASS", "match": "PATH", "value": "/mcp", "priority": 3, "enabled": true},
        {"ruleId": 2012, "action": "PASS", "match": "PATH", "value": "/api/beszel/agent-connect", "priority": 3, "enabled": true},
        {"ruleId": 2011, "action": "ACCEPT", "match": "PATH", "value": "/share/*", "priority": 4, "enabled": true},
        {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
      ], "pagination": {"total": 9, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Rules retrieved successfully", "status": 200}
    EOT
  }
}

# GET /v1/org/{org}/site-resources?pageSize=1000 : les quatre ressources
# privées déclarées dans private_resources.tf et les deux passerelles VPN
# faites dans l'UI (mode gateway), que lit l'audit vpn_gateways. vpn-flip sort
# par le site flip ; le site de vpn n'est pas vérifié par l'audit, celui-ci
# n'est qu'un exemple.
override_data {
  target = data.http.pangolin_site_resources
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"siteResources": [
        {"siteResourceId": 1, "niceId": "bbox", "name": "BBOX", "mode": "http", "destination": "192.168.1.254", "enabled": true,
         "alias": null, "tcpPortRangeString": "443,80", "udpPortRangeString": "", "disableIcmp": true,
         "siteIds": [1], "siteNames": ["proxmox-lxc"], "siteNiceIds": ["proxmox-lxc"], "siteOnlines": [true], "labels": []},
        {"siteResourceId": 2, "niceId": "docker-apps", "name": "Docker Apps", "mode": "host", "destination": "192.168.1.216", "enabled": true,
         "alias": "docker-apps.internal", "tcpPortRangeString": "22", "udpPortRangeString": "*", "disableIcmp": true,
         "siteIds": [1], "siteNames": ["proxmox-lxc"], "siteNiceIds": ["proxmox-lxc"], "siteOnlines": [true], "labels": []},
        {"siteResourceId": 3, "niceId": "raspberry-pi", "name": "Raspberry PI", "mode": "host", "destination": "192.168.1.96", "enabled": true,
         "alias": "pi.internal", "tcpPortRangeString": "22", "udpPortRangeString": "*", "disableIcmp": false,
         "siteIds": [1], "siteNames": ["proxmox-lxc"], "siteNiceIds": ["proxmox-lxc"], "siteOnlines": [true], "labels": []},
        {"siteResourceId": 4, "niceId": "flip", "name": "Flip", "mode": "host", "destination": "10.0.1.10", "enabled": true,
         "alias": "flip.internal", "tcpPortRangeString": "22", "udpPortRangeString": "", "disableIcmp": true,
         "siteIds": [5], "siteNames": ["flip"], "siteNiceIds": ["flip"], "siteOnlines": [true], "labels": []},
        {"siteResourceId": 5, "niceId": "vpn", "name": "vpn", "mode": "gateway", "destination": "0.0.0.0/0", "enabled": true,
         "alias": null, "tcpPortRangeString": "*", "udpPortRangeString": "*", "disableIcmp": false,
         "siteIds": [1], "siteNames": ["proxmox-lxc"], "siteNiceIds": ["proxmox-lxc"], "siteOnlines": [true], "labels": []},
        {"siteResourceId": 6, "niceId": "vpn-flip", "name": "vpn-flip", "mode": "gateway", "destination": "0.0.0.0/0", "enabled": true,
         "alias": null, "tcpPortRangeString": "*", "udpPortRangeString": "*", "disableIcmp": false,
         "siteIds": [5], "siteNames": ["flip"], "siteNiceIds": ["flip"], "siteOnlines": [true], "labels": []}
      ], "pagination": {"total": 6, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Site resources retrieved successfully", "status": 200}
    EOT
  }
}

# --- Identifiants calculés, fixés et distincts -----------------------------

# Sites. flip porte les identifiants Newt que flip.yml lit dans ce state.
override_resource {
  target = pangolin_site.proxmox_lxc
  values = { id = 1, newt_id = "newt-proxmox-lxc", newt_secret = "secret-proxmox-lxc" }
}

override_resource {
  target = pangolin_site.pangolin
  values = { id = 2 }
}

override_resource {
  target = pangolin_site.proxmox_docker
  values = { id = 3, newt_id = "newt-proxmox-docker", newt_secret = "secret-proxmox-docker" }
}

override_resource {
  target = pangolin_site.pi
  values = { id = 4, newt_id = "newt-pi", newt_secret = "secret-pi" }
}

override_resource {
  target = pangolin_site.flip
  values = { id = 5, newt_id = "newt-flip", newt_secret = "secret-flip" }
}

override_resource {
  target = pangolin_site.nas
  values = { id = 6, newt_id = "newt-nas", newt_secret = "secret-nas" }
}

override_resource {
  target = pangolin_role.jellyfin
  values = { id = 90 }
}

override_resource {
  target = pangolin_site_resource.jellyfin
  values = { id = 91 }
}

# Ressources publiques : un identifiant par instance de pangolin_resource.website
# (une surcharge peut viser une seule instance d'un for_each, vérifié sur
# OpenTofu 1.13), ceux de l'API quand un commentaire du code les cite.
override_resource {
  target = pangolin_resource.website["betisier"]
  values = { id = 21 }
}

override_resource {
  target = pangolin_resource.website["docs"]
  values = { id = 84 }
}

override_resource {
  target = pangolin_resource.website["dawarich"]
  values = { id = 60 }
}

override_resource {
  target = pangolin_resource.website["homepage"]
  values = { id = 66, full_domain = "home.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["demo_planning"]
  values = { id = 81, full_domain = "demo-planning.sylvain.dev" }
}

override_resource {
  target = pangolin_resource.website["demo_planning_kc"]
  values = { id = 82, full_domain = "demo-planning-kc.sylvain.dev" }
}

override_resource {
  target = pangolin_resource.website["flip_planning"]
  values = { id = 80, full_domain = "flip-planning.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["immich"]
  values = { id = 10 }
}

override_resource {
  target = pangolin_resource.website["immich_swipe"]
  values = { id = 23 }
}

override_resource {
  target = pangolin_resource.website["immich_selfie_timelapse"]
  values = { id = 24 }
}

override_resource {
  target = pangolin_resource.website["homebox"]
  values = { id = 69 }
}

override_resource {
  target = pangolin_resource.website["papra"]
  values = { id = 73 }
}

override_resource {
  target = pangolin_resource.website["speedtest_tracker"]
  values = { id = 70 }
}

override_resource {
  target = pangolin_resource.website["grocy"]
  values = { id = 74 }
}

override_resource {
  target = pangolin_resource.website["ntfy"]
  values = { id = 71 }
}

override_resource {
  target = pangolin_resource.website["victoria_logs"]
  values = { id = 72, full_domain = "logs.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["karakeep"]
  values = { id = 62 }
}

override_resource {
  target = pangolin_resource.website["monica"]
  values = { id = 31 }
}

override_resource {
  target = pangolin_resource.website["beszel"]
  values = { id = 65 }
}

override_resource {
  target = pangolin_resource.website["nextcloud"]
  values = { id = 11 }
}

override_resource {
  target = pangolin_resource.website["stirling_pdf"]
  values = { id = 68 }
}

override_resource {
  target = pangolin_resource.website["paperless"]
  values = { id = 40 }
}

override_resource {
  target = pangolin_resource.website["promptoramix"]
  values = { id = 83, full_domain = "promptoramix.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["rss"]
  values = { id = 32 }
}

override_resource {
  target = pangolin_resource.website["trek"]
  values = { id = 61, full_domain = "travels.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["wiki"]
  values = { id = 33 }
}

override_resource {
  target = pangolin_resource.website["wishlist"]
  values = { id = 63 }
}

# Jetons d'accès : ceux des clients MCP de TREK, et ceux des healthchecks de
# Flip Planning, un par environnement.
override_resource {
  target = pangolin_resource_access_token.trek_mcp_clients
  values = { id = "tok-trek-mcp", token = "jeton-trek-mcp" }
}

# Un identifiant commun aux deux agents distants de Beszel.
override_resource {
  target = pangolin_resource_access_token.beszel_agents
  values = { id = "tok-beszel-agent", token = "jeton-beszel-agent" }
}

# Un identifiant commun aux deux agents de journaux distants.
override_resource {
  target = pangolin_resource_access_token.log_agents
  values = { id = "tok-log-agent", token = "jeton-log-agent" }
}

override_resource {
  target = pangolin_resource_access_token.healthcheck["flip_planning"]
  values = { id = "tok-flip-planning", token = "jeton-flip-planning" }
}

override_resource {
  target = pangolin_resource_access_token.healthcheck["demo_planning"]
  values = { id = "tok-demo-planning", token = "jeton-demo-planning" }
}

# Uptime Kuma : canal de notification et dossiers.
override_resource {
  target = uptimekuma_notification_ntfy.ntfy
  values = { id = 13 }
}

override_resource {
  target = uptimekuma_notification_telegram.supervision
  values = { id = 9 }
}

override_resource {
  target = uptimekuma_monitor_group.backups
  values = { id = 11 }
}

override_resource {
  target = uptimekuma_monitor_group.self_hosted
  values = { id = 12 }
}

# Jetons push : un par moniteur (une surcharge par instance de
# uptimekuma_monitor_push.backup), pour prouver que chaque sortie lue par
# Ansible pointe sur SON moniteur (la démo a déjà poussé sur celui de la
# production).
override_resource {
  target = uptimekuma_monitor_push.backup["betisier"]
  values = { push_token = "push-betisier" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["dawarich"]
  values = { push_token = "push-dawarich" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["demo_planning"]
  values = { push_token = "push-demo-planning" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["flip_planning"]
  values = { push_token = "push-flip-planning" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["immich"]
  values = { push_token = "push-immich" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["monica"]
  values = { push_token = "push-monica" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_monica
  values = { push_token = "push-cron-monica" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["nextcloud"]
  values = { push_token = "push-nextcloud" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_pangolin
  values = { push_token = "push-pangolin" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_jellyfin
  values = { push_token = "push-jellyfin" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_geoip
  values = { push_token = "push-cron-geoip" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_betisier_reset
  values = { push_token = "push-cron-betisier-reset" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_exemple_planning_reset
  values = { push_token = "push-cron-exemple-planning-reset" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_nas_cert
  values = { push_token = "push-cron-nas-cert" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_kdrive_sync
  values = { push_token = "push-cron-kdrive-sync" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_vzdump_restore_test
  values = { push_token = "push-cron-vzdump-restore-test" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_updates["pve"]
  values = { push_token = "push-cron-pve-updates" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_updates["docker"]
  values = { push_token = "push-cron-docker-updates" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_updates["pi"]
  values = { push_token = "push-cron-pi-updates" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_updates["flip"]
  values = { push_token = "push-cron-flip-updates" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_updates["pangolin"]
  values = { push_token = "push-cron-pangolin-updates" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_dns["pi"]
  values = { push_token = "push-cron-dns-pi" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_dns["lxc"]
  values = { push_token = "push-cron-dns-lxc" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_ntfy_subscribers
  values = { push_token = "push-cron-ntfy-subscribers" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["paperless"]
  values = { push_token = "push-paperless" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["papra"]
  values = { push_token = "push-papra" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["rss"]
  values = { push_token = "push-rss" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["trek"]
  values = { push_token = "push-trek" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["karakeep"]
  values = { push_token = "push-karakeep" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["homebox"]
  values = { push_token = "push-homebox" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["speedtest_tracker"]
  values = { push_token = "push-speedtest-tracker" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["grocy"]
  values = { push_token = "push-grocy" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["ntfy"]
  values = { push_token = "push-ntfy" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["beszel"]
  values = { push_token = "push-beszel" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["wiki"]
  values = { push_token = "push-wiki" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["wishlist"]
  values = { push_token = "push-wishlist" }
}

override_resource {
  target = uptimekuma_monitor_push.ssh_login["docker"]
  values = { push_token = "push-ssh-docker" }
}

override_resource {
  target = uptimekuma_monitor_push.ssh_login["flip"]
  values = { push_token = "push-ssh-flip" }
}

override_resource {
  target = uptimekuma_monitor_push.ssh_login["pangolin"]
  values = { push_token = "push-ssh-pangolin" }
}

override_resource {
  target = uptimekuma_monitor_push.ssh_login["pi"]
  values = { push_token = "push-ssh-pi" }
}

override_resource {
  target = uptimekuma_monitor_push.ssh_login["newt-lxc"]
  values = { push_token = "push-ssh-newt-lxc" }
}

# ===========================================================================
# Runs `plan` : valeurs issues de la configuration
# ===========================================================================

# Moins de bruit de sondes (2026-10-29) : à une sonde par minute, les
# healthchecks Uptime Kuma faisaient 990k des 1,52M lignes du journal des
# requêtes de Pangolin, et Newt sondait sans fin les cibles des applis en
# pause. Chaque moniteur HTTP sonde toutes les 5 minutes et ne passe DOWN
# qu'après un nouvel essai une minute plus tard ; une sonde Pangolin par
# minute sur une cible active, aucune sur celle d'une appli en pause.
run "probes_are_sparse_and_paused_apps_are_not_probed" {
  command = plan

  # Tout moniteur HTTP du module, écrit à la main ou généré, lit sa cadence et
  # ses essais dans local.http_probe (uptime_globals.tf), qui seul fixe les
  # valeurs.
  assert {
    condition = alltrue(flatten([
      for f in fileset(path.module, "*.tf") : [
        for block in regexall("(?s)resource\\s+\"uptimekuma_monitor_http(?:_keyword)?\"\\s+\"\\w+\"\\s+\\{.*?\\n\\}", file("${path.module}/${f}")) : [
          for attribute in ["interval", "max_retries", "retry_interval", "resend_interval"] :
          length(regexall("(?m)^\\s*${attribute}\\s*=\\s*local\\.http_probe\\.${attribute}\\s*$", block)) == 1
        ]
      ]
    ]))
    error_message = "Un moniteur uptimekuma_monitor_http(_keyword) ne lit pas interval, max_retries, retry_interval et resend_interval dans local.http_probe."
  }

  assert {
    condition = alltrue([
      for key, t in pangolin_target.website :
      t.hc_enabled == lookup(local.websites[local.website_targets[key].website], "enabled", true)
    ])
    error_message = "La sonde Pangolin d'une cible est coupée exactement quand son appli est en pause (enabled = false)."
  }
}

# Chaque cible sondée déclare hc_scheme / hc_mode / hc_port. Ils sont
# optionnels+calculés : non déclarés, Pangolin a stocké NULL pour gramps et
# scanopy, la sonde ne pouvait jamais réussir et les deux sites ont servi
# "no available server" pendant que `tofu plan` ne voyait rien.
#
# Les cibles des applications sont les instances de pangolin_target.website
# (websites.tf), toutes sondées sauf celles d'une appli en pause, dont la
# sonde est coupée mais garde ses réglages. hc_hostname est explicite et égal
# à `ip` : la sonde envoie le bon Host au bon conteneur, le provider ne le
# déduit pas de `ip`.
run "every_probed_target_declares_scheme_mode_and_port" {
  command = plan

  assert {
    condition = alltrue([
      for t in values(pangolin_target.website) :
      contains(["http", "https"], t.hc_scheme)
      && t.hc_mode == "http"
      && t.hc_port != null
      && t.hc_hostname == t.ip
    ])
    error_message = "Une cible sondée n'a pas hc_scheme (http/https), hc_mode = \"http\", hc_port, ou un hc_hostname égal à son ip : Pangolin stockerait NULL et la sonde échouerait toujours."
  }

  # local.website_targets fusionne par merge() les clés des applications et les
  # "<app>_<suffixe>" de leurs sub_targets : une collision (un sub_target `kc`
  # de demo_planning contre l'application demo_planning_kc) écraserait une
  # cible sans un mot. Aucune clé perdue : autant de cibles que déclarées.
  assert {
    condition = length(local.website_targets) == sum(concat([0], [
      for website in values(local.websites) :
      (lookup(website, "target", null) == null ? 0 : 1) + length(lookup(website, "sub_targets", {}))
    ]))
    error_message = "Deux cibles de local.website_targets ont la même clé (une application et le sub_target d'une autre) : l'une écrase l'autre."
  }

  # Filet par fichier, indépendant de local.websites : tout bloc
  # `pangolin_target` du module, généré (websites.tf) ou écrit à la main
  # (celui qui viendra), qui ne coupe pas sa sonde en dur déclare aussi
  # hc_scheme, hc_mode, hc_port et hc_hostname, et sa cadence (hc_interval,
  # hc_unhealthy_interval), optionnelle+calculée elle aussi : non déclarée,
  # elle prendrait ce que l'API renvoie sans que le plan le voie.
  assert {
    condition = alltrue(flatten([
      for f in fileset(path.module, "*.tf") : [
        for block in regexall("(?s)resource\\s+\"pangolin_target\"\\s+\"\\w+\"\\s+\\{.*?\\n\\}", file("${path.module}/${f}")) :
        length(regexall("(?m)^\\s*hc_enabled\\s*=\\s*false\\s*$", block)) > 0 || alltrue([
          for attribute in ["hc_scheme", "hc_mode", "hc_port", "hc_hostname", "hc_interval", "hc_unhealthy_interval"] :
          length(regexall("(?m)^\\s*${attribute}\\s*=", block)) > 0
        ])
      ]
      ])) && length(flatten([
      for f in fileset(path.module, "*.tf") :
      regexall("resource\\s+\"pangolin_target\"\\s+\"", file("${path.module}/${f}"))
    ])) >= 1
    error_message = "Un bloc pangolin_target active sa sonde sans déclarer hc_scheme, hc_mode, hc_port, hc_hostname, hc_interval et hc_unhealthy_interval : Pangolin stockerait NULL (la sonde échouerait toujours) ou sa propre cadence."
  }
}

# Routage par chemin : la cible attrape-tout "/" doit avoir le numéro de
# priorité le PLUS BAS de sa ressource, sinon elle avale /db, /mail, /assets
# et /auth. Les priorités d'une même ressource sont toutes distinctes. Calculé
# sur chaque ressource qui a plusieurs cibles (sub_targets), sans liste.
run "catch_all_target_has_lowest_priority" {
  command = plan

  assert {
    condition = alltrue([
      for group in values({
        for key, t in pangolin_target.website : local.website_targets[key].website => t...
      }) :
      length(group) == 1 || (
        length([for t in group : t if t.path == "/"]) == 1
        # try : sans cible "/" (ou avec deux), one() échoue ; l'assertion doit
        # échouer avec son message, pas le run sur une erreur d'évaluation.
        && try(alltrue([
          for t in group :
          t.path == "/" || t.priority > one([for c in group : c.priority if c.path == "/"])
        ]), false)
        && length(distinct([for t in group : t.priority])) == length(group)
        && length(distinct([for t in group : t.path])) == length(group)
        && alltrue([for t in group : t.path_match_type == "prefix"])
      )
    ])
    error_message = "Une ressource multi-chemins n'a pas exactement une cible \"/\" au numéro de priorité le plus bas, ou ses cibles n'ont pas des priorités et des chemins distincts, en correspondance par préfixe."
  }

  # Garde-fou du test lui-même : sans ressource multi-chemins, l'assertion
  # ci-dessus serait vraie par construction.
  assert {
    condition     = length([for website in values(local.websites) : website if length(lookup(website, "sub_targets", {})) > 0]) >= 3
    error_message = "Les trois environnements de Flip Planning routent par chemin : ce run doit en voir au moins trois."
  }
}

# Les règles pays sont dérivées de la configuration : chaque ressource de
# local.managed_resources (les ressources gérées) a PASS FR, PASS DE et DROP ALL.
run "country_rules_cover_every_resource" {
  command = plan

  assert {
    condition     = length(pangolin_resource_rule.block_country) == length(local.managed_resources)
    error_message = "Il faut une règle DROP COUNTRY ALL par ressource couverte."
  }

  assert {
    condition     = length(pangolin_resource_rule.allow_countries) == length(local.managed_resources) * 2
    error_message = "Il faut une règle PASS par ressource couverte et par pays autorisé (FR, DE)."
  }

  assert {
    condition = alltrue([
      for name in keys(local.managed_resources) :
      contains(keys(pangolin_resource_rule.block_country), name)
      && contains(keys(pangolin_resource_rule.allow_countries), "${name}-FR")
      && contains(keys(pangolin_resource_rule.allow_countries), "${name}-DE")
    ])
    error_message = "Une ressource publique n'a pas ses trois règles pays (PASS FR, PASS DE, DROP ALL)."
  }

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.block_country :
      rule.action == "DROP" && rule.match == "COUNTRY" && rule.value == "ALL" && rule.priority == 99
    ])
    error_message = "Le catch-all doit être DROP COUNTRY ALL à la priorité 99."
  }

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.allow_countries :
      rule.action == "PASS" && rule.match == "COUNTRY" && rule.enabled == true
      && rule.priority == (rule.value == "FR" ? 10 : 11)
      && contains(["FR", "DE"], rule.value)
    ])
    error_message = "Les règles pays doivent être PASS COUNTRY FR (priorité 10) et DE (priorité 11)."
  }
}

# Un pays de voyage ouvre une règle PASS par ressource couverte, à sa propre
# priorité (20), sans toucher aux règles FR/DE ni à leurs priorités. Dates hors
# d'atteinte pour que le run ne dépende pas du jour où il tourne.
run "travel_countries_open_a_temporary_band" {
  command = plan

  variables {
    travel_countries = {
      IT = "2999-01-01T00:00:00Z"
      GB = "2999-01-01T00:00:00Z"
    }
  }

  assert {
    condition     = length(pangolin_resource_rule.allow_countries) == length(local.managed_resources) * 4
    error_message = "Chaque pays de voyage actif ajoute une règle PASS par ressource couverte."
  }

  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.allow_countries :
      rule.action == "PASS" && rule.match == "COUNTRY" && rule.enabled == true
      && endswith(key, "-${rule.value}")
      && rule.priority == lookup({ FR = 10, DE = 11, GB = 20, IT = 20 }, rule.value, 0)
    ])
    error_message = "FR et DE gardent 10 et 11 ; tous les pays de voyage partagent la priorité 20."
  }

  assert {
    condition     = length(pangolin_resource_rule.block_country) == length(local.managed_resources)
    error_message = "Un voyage n'ajoute aucune règle DROP : le catch-all reste unique par ressource."
  }

  assert {
    condition = alltrue([
      for name in keys(local.managed_resources) :
      contains(keys(pangolin_resource_rule.allow_countries), "${name}-GB")
      && contains(keys(pangolin_resource_rule.allow_countries), "${name}-IT")
    ])
    error_message = "Chaque ressource couverte s'ouvre aux pays de voyage actifs."
  }
}

# La priorité d'un pays de voyage ne dépend pas des autres : en ajouter ou en
# voir expirer un ne met pas à jour les règles de ceux qui restent ouverts.
run "travel_country_priority_ignores_the_other_trips" {
  command = plan

  variables {
    travel_countries = {
      ES = "2999-01-01T00:00:00Z"
      GB = "2999-01-01T00:00:00Z"
      IT = "2000-01-01T00:00:00Z"
    }
  }

  expect_failures = [check.travel_countries_stale]

  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.allow_countries :
      rule.priority == 20 if contains(["ES", "GB"], rule.value)
    ])
    error_message = "GB doit rester à 20 quand ES s'ouvre avant lui dans l'ordre alphabétique et qu'IT expire."
  }

  assert {
    condition     = length(pangolin_resource_rule.allow_countries) == length(local.managed_resources) * 4
    error_message = "ES et GB actifs, IT expiré : deux pays de voyage en plus de FR et DE."
  }
}

# Un voyage terminé ne produit plus aucune règle au plan suivant, et le check
# rappelle de retirer l'entrée. Un pays déjà autorisé n'est pas dupliqué.
run "expired_travel_country_opens_nothing" {
  command = plan

  variables {
    travel_countries = {
      GB = "2000-01-01T00:00:00Z"
      FR = "2999-01-01T00:00:00Z"
    }
  }

  expect_failures = [check.travel_countries_stale]

  assert {
    condition     = length(pangolin_resource_rule.allow_countries) == length(local.managed_resources) * 2
    error_message = "Un pays de voyage échu ou déjà autorisé ne doit ajouter aucune règle."
  }

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.allow_countries :
      rule.priority == (rule.value == "FR" ? 10 : 11)
    ])
    error_message = "FR, même listé comme pays de voyage, garde sa règle permanente à la priorité 10."
  }
}

# La bande de priorités de rules.tf : la priorité 1 est au DROP antislash, les
# règles qui doivent décider quelle que soit l'origine (ACCEPT par chemin, PASS
# /mcp de TREK) sont entre 2 et 8, les ACCEPT d'IP maison à 9, tous AVANT les
# PASS pays (10-11, voyages à 20), et le DROP ALL en dernier (99).
run "bypass_rules_sit_in_their_priority_band" {
  command = plan

  # La procédure tRPC est écrite en entier : un joker dans ce segment laisserait
  # passer un lot `publicBookmarks.x,apiKeys.exchange`, échange mot de passe
  # contre clé d'API ouvert au monde entier.
  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.path_bypass :
      !strcontains(rule.value, "/api/trpc/") || !strcontains(rule.value, "*")
    ])
    error_message = "Aucun joker sous /api/trpc/ : tRPC regroupe plusieurs procédures dans un seul segment."
  }

  # Les trois règles par chemin autonomes (/mcp de TREK, les points d'entrée
  # des agents Beszel et de journaux) sont des PASS : elles sautent les règles
  # pays mais gardent l'authentification Pangolin (SSO ou jeton d'accès).
  # Jamais un ACCEPT ni un joker, toujours avant les règles pays ; Beszel et
  # VictoriaLogs n'ont aucune ouverture par chemin.
  assert {
    condition = alltrue([
      for rule in [pangolin_resource_rule.trek_mcp, pangolin_resource_rule.beszel_agent_connect, pangolin_resource_rule.victoria_logs_insert] :
      rule.action == "PASS" && rule.match == "PATH" && rule.enabled == true
      && !strcontains(rule.value, "*")
      && rule.priority >= 2 && rule.priority < 10
      ]) && [
      for rule in [pangolin_resource_rule.trek_mcp, pangolin_resource_rule.beszel_agent_connect, pangolin_resource_rule.victoria_logs_insert] : rule.value
    ] == ["/mcp", "/api/beszel/agent-connect", "/insert/jsonline"] && !contains(keys(local.path_bypasses), "Beszel") && !contains(keys(local.path_bypasses), "VictoriaLogs")
    error_message = "/mcp de TREK, /api/beszel/agent-connect et /insert/jsonline doivent être des PASS (pas des ACCEPT) sur ces chemins exacts, avant les règles pays ; rien de Beszel ni de VictoriaLogs dans local.path_bypasses."
  }

  # L'override donne le même identifiant à toutes les instances d'une règle
  # for_each : l'audit d'inventaire ne verrait pas qu'une d'elles manque à
  # declared_extra_rules. D'où une comparaison sur les chemins, connus au plan.
  assert {
    condition = alltrue([
      for rule in concat(
        values(pangolin_resource_rule.path_bypass),
        values(pangolin_resource_rule.backslash_guard),
        [pangolin_resource_rule.trek_mcp, pangolin_resource_rule.beszel_agent_connect, pangolin_resource_rule.victoria_logs_insert],
      ) :
      contains([for declared in local.declared_extra_rules : declared.value], rule.value)
    ])
    error_message = "Chaque règle par chemin doit figurer dans local.declared_extra_rules, sinon l'audit d'inventaire fait échouer le plan en production."
  }

  assert {
    condition = alltrue([
      for rule in [
        pangolin_resource_rule.immich_home_ip,
        pangolin_resource_rule.dawarich_home_ip,
        pangolin_resource_rule.trek_home_ip,
      ] :
      rule.action == "ACCEPT" && rule.match == "IP" && rule.value == "203.0.113.10"
      && rule.priority == 9 && rule.enabled == true
    ])
    error_message = "Les ACCEPT de l'IP maison doivent être à la priorité 9, devant les PASS pays (10-11) : derrière, l'IP maison (française) n'atteignait jamais la règle."
  }
}

# Les ouvertures par chemin de local.path_bypasses (rules.tf) : exactement les
# chemins relus dans les sources de chaque application, rien de plus large.
# Ajouter un chemin oblige à le lister ici.
run "path_bypasses_open_exactly_the_reviewed_paths" {
  command = plan

  assert {
    condition = toset(keys(pangolin_resource_rule.path_bypass)) == toset([
      "Dawarich /s/*",
      "Dawarich /api/v1/shared/*",
      "Dawarich /cable",
      "Dawarich /shared/*",
      "Dawarich /api/v1/maps/hexagons",
      "Dawarich /assets/*",
      "Dawarich /maps_maplibre/*",
      "Dawarich /site.webmanifest",
      "Dawarich /favicon.ico",
      "Demo Planning /mcp/*",
      "Demo Planning KC /auth/*",
      "Flip Planning /mcp/*",
      "Karakeep /public/lists/*",
      "Karakeep /_next/static/*",
      "Karakeep /api/public/*",
      "Karakeep /api/trpc/publicBookmarks.getPublicBookmarksInList",
      "Karakeep /api/v1/rss/lists/*",
      "Monica CRM /dav/*",
      "Monica CRM /.well-known/carddav",
      "Monica CRM /.well-known/caldav",
      "nextcloud /status.php",
      "nextcloud /index.php/204",
      "nextcloud /remote.php/*",
      "nextcloud /ocs/v1.php/*",
      "nextcloud /ocs/v2.php/*",
      "nextcloud /index.php/login/v2",
      "nextcloud /login/v2/poll",
      "nextcloud /index.php/login/v2/poll",
      "nextcloud /index.php/core/wipe/*",
      "nextcloud /index.php/core/preview",
      "nextcloud /index.php/core/preview.png",
      "nextcloud /index.php/apps/files_trashbin/preview",
      "nextcloud /index.php/apps/files_versions/preview",
      "nextcloud /index.php/apps/files/api/v1/thumbnail/*",
      "nextcloud /.well-known/caldav",
      "nextcloud /.well-known/carddav",
      "nextcloud /s/*",
      "nextcloud /index.php/s/*",
      "nextcloud /public.php/*",
      "nextcloud /apps/files_sharing/*",
      "nextcloud /index.php/apps/files_sharing/*",
      "nextcloud /apps/theming/*",
      "nextcloud /index.php/apps/theming/*",
      "nextcloud /dist/*",
      "nextcloud /core/css/*",
      "nextcloud /core/fonts/*",
      "nextcloud /core/img/*",
      "nextcloud /core/js/*",
      "nextcloud /core/l10n/*",
      "nextcloud /core/vendor/*",
      "nextcloud /apps/*/js/*",
      "nextcloud /apps/*/css/*",
      "nextcloud /apps/*/img/*",
      "nextcloud /apps/*/l10n/*",
      "nextcloud /custom_apps/*/js/*",
      "nextcloud /custom_apps/*/css/*",
      "nextcloud /custom_apps/*/img/*",
      "nextcloud /custom_apps/*/l10n/*",
      "nextcloud /apps/files_pdfviewer/*",
      "nextcloud /index.php/apps/files_pdfviewer/*",
      "nextcloud /csrftoken",
      "nextcloud /index.php/csrftoken",
      "nextcloud /index.php/apps/files/preview-service-worker.js",
      "nextcloud /apps/text/public/*",
      "ntfy /",
      "ntfy /*/json",
      "ntfy /*/ws",
      "ntfy /*/auth",
      "ntfy /uptime-kuma",
      "ntfy /scripts",
      "ntfy /github",
      "Paperless-ngx /share/*",
      "Promptoramix /*",
      "TREK /.well-known/oauth-protected-resource/mcp",
      "TREK /.well-known/oauth-protected-resource",
      "TREK /.well-known/oauth-authorization-server",
      "TREK /.well-known/oauth-authorization-server/mcp",
      "TREK /.well-known/openid-configuration",
      "TREK /mcp/.well-known/oauth-protected-resource",
      "TREK /mcp/.well-known/oauth-authorization-server",
      "TREK /mcp/.well-known/openid-configuration",
      "TREK /oauth/token",
      "TREK /assets/*",
      "TREK /theme-boot.js",
      "TREK /shell-guard.js",
      "TREK /icons/icon.svg",
      "TREK /icons/icon-white.svg",
      "TREK /icons/apple-touch-icon-180x180.png",
      "TREK /shared/*",
      "TREK /api/shared/*",
      "TREK /public/journey/*",
      "TREK /api/public/journey/*",
      "TREK /uploads/covers/*",
      "TREK /uploads/places/*",
      "Wishlist /lists/*",
      "Wishlist /_app/*",
      "Wishlist /fonts/*",
      "Wishlist /api/assets/*",
      "Wishlist /api/users/public",
      "Wishlist /api/lists/*/items/*/claims",
    ])
    error_message = "Les chemins ouverts sans SSO ont changé : relire la liste dans website_<app>.tf et la mettre à jour ici."
  }

  # Les tables fusionnées par merge() ne doivent partager aucun chemin : une
  # clé commune garderait une seule des deux priorités, sans un mot. Même
  # contrôle sur la fusion finale de path_bypass_rules.
  assert {
    condition = (
      length(local.path_bypasses["TREK"]) == length(local.trek_mcp_public_paths) + length(local.trek_share_paths)
      && length(local.path_bypasses["ntfy"]) == 4 + length(local.ntfy_publish_topics)
      && length(local.path_bypass_rules) == sum([for paths in values(local.path_bypasses) : length(paths)])
    )
    error_message = "Deux tables de chemins fusionnées dans local.path_bypasses partagent une clé : l'une écrase l'autre."
  }

  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.path_bypass :
      rule.action == "ACCEPT" && rule.match == "PATH"
      && rule.enabled == !anytrue([for name in local.php_lockdown_path_bypasses : startswith(key, "${name} ")])
      && rule.priority >= 2 && rule.priority < 10
    ])
    error_message = "Les ouvertures par chemin sont des ACCEPT PATH dans la bande 2 à 9 : derrière le DROP antislash (1), devant les règles pays (10)."
  }

  # Aucune ouverture ne doit rendre une interface d'administration ou d'API
  # entière : ni racine, ni `/api/*`, ni `/i/*` de FreshRSS. Seule exception,
  # décidée et validée par l'utilisateur : Promptoramix, ouverte en entier
  # (`/*`) aux fonctions Supabase du tournoi Linkx, de n'importe quel pays,
  # sans interface ni compte, et dont chaque requête est signée en HMAC
  # (website_promptoramix.tf).
  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.path_bypass :
      key == "Promptoramix /*" || !contains(["/*", "/api/*", "/api/v1/*", "/i/*", "/p/*"], rule.value)
    ])
    error_message = "Une ouverture par chemin couvre toute l'application ou toute son API."
  }

  # Nextcloud : les clients n'ont que la moitié « client » du login flow v2
  # (démarrage et poll) ; la moitié navigateur (flow, grant, apptoken), le
  # formulaire de connexion et les pages de réglages restent derrière le SSO,
  # comme le front controller, l'ensemble de /apps et /core/ajax (l'updater
  # web, sans login pendant une mise à jour en attente). Ce run ne dit rien de
  # ce que porte OCS, ouvert en entier pour les clients : avec un mot de passe
  # d'application administrateur, l'API de provisioning y répond aussi.
  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.path_bypass :
      !startswith(key, "nextcloud ") || (
        !contains(["/index.php/*", "/apps/*", "/index.php/apps/*", "/core/*", "/index.php/core/*", "/custom_apps/*", "/login", "/index.php/login", "/login/*", "/index.php/login/*", "/login/v2/*", "/index.php/login/v2/*"], rule.value)
        && length(regexall("/ajax(/|$)", rule.value)) == 0
        && length(regexall("/(flow|grant|apptoken|settings)(/|$)", rule.value)) == 0
      )
    ])
    error_message = "Nextcloud : le login web, la moitié navigateur du login flow v2 et les réglages doivent rester derrière le SSO."
  }
}

# Pangolin ne normalise pas l'antislash, que Node transforme en `/` : chaque
# ressource qui a une règle par chemin a son DROP en priorité 1, seul dans sa
# case, donc évalué avant toutes les autres. Qu'aucune ressource à règle par
# chemin n'en manque, c'est le run apply tied_rules_share_their_action qui le
# vérifie, sur les règles réellement déclarées.
run "backslash_guard_covers_every_path_rule" {
  command = plan

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.backslash_guard :
      rule.action == "DROP" && rule.match == "PATH" && rule.value == "/*/*%5C*/*"
      && rule.priority == 1 && rule.enabled == true
    ])
    error_message = "Le garde antislash est un DROP PATH /*/*%5C*/* en priorité 1."
  }

  assert {
    condition = alltrue([
      for rule in concat(
        [pangolin_resource_rule.trek_mcp, pangolin_resource_rule.beszel_agent_connect, pangolin_resource_rule.victoria_logs_insert],
        values(pangolin_resource_rule.exemple_planning_drop),
        values(pangolin_resource_rule.path_bypass),
      ) : rule.priority > 1
    ])
    error_message = "La priorité 1 est réservée au DROP antislash : une règle par chemin à égalité avec lui serait évaluée dans un ordre arbitraire."
  }
}

# La vitrine publique (website_exemple_planning.tf) n'a ni SSO ni mot de passe
# admin secret : ses DROP sont tout ce qui sépare un visiteur du MCP, de
# l'import SQL (utilisateur Postgres superutilisateur), du calcul synchrone et
# de l'envoi de Mailpit. Liste fermée, toutes devant les règles pays (une DROP
# derrière un PASS ne serait jamais lue) et derrière le garde antislash, et
# aucun ACCEPT de chemin sur la ressource qui passerait avant elles.
run "public_showcase_drops_what_its_shared_admin_must_not_reach" {
  command = plan

  assert {
    condition     = pangolin_resource.website["exemple_planning"].sso == false
    error_message = "La vitrine est sans SSO par conception : c'est ce qui rend ses DROP nécessaires."
  }

  assert {
    condition = { for key, rule in pangolin_resource_rule.exemple_planning_drop : key => rule.value } == {
      mcp          = "/mcp*/*"
      database     = "/api*/database*/*"
      solve_sync   = "/api*/solve*"
      mailpit_send = "/mail/api/v1/send"
      debug        = "/api*/debug*/*"
      link_check   = "/mail/api/v1/message/*/link-check"
    }
    error_message = "Les DROP de la vitrine ont changé : MCP, import/export SQL, calcul synchrone, Débogage, envoi et vérification de liens de Mailpit, ni plus ni moins (les webhooks sont coupés dans l'application)."
  }

  # Les cibles visent les conteneurs par nom sur le réseau newt : le préfixe
  # que flip.yml donne à la vitrine.
  assert {
    condition = (
      length(regexall("flip_planning_container_prefix: exemple-planning\\n", file("${path.module}/../../ansible/flip.yml"))) == 1
      && pangolin_target.website["exemple_planning"].ip == "exemple-planning"
      && pangolin_target.website["exemple_planning_mailpit"].ip == "exemple-planning-mailpit"
      && pangolin_target.website["exemple_planning_assets"].ip == "exemple-planning-assets"
    )
    error_message = "Les cibles de la vitrine doivent suivre flip_planning_container_prefix de son entrée dans ansible/flip.yml (exemple-planning)."
  }

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.exemple_planning_drop :
      rule.action == "DROP" && rule.match == "PATH" && rule.enabled == true
      && rule.priority > 1 && rule.priority < 10
    ])
    error_message = "Les règles de la vitrine sont des DROP PATH actives, entre le garde antislash (1) et les règles pays (10)."
  }

  assert {
    condition     = !contains(keys(local.path_bypasses), "Exemple Planning")
    error_message = "La vitrine ne doit avoir aucun ACCEPT de chemin : il passerait avant ses DROP ou à côté d'eux."
  }
}

# Pangolin départage deux règles de même priorité selon l'ordre de sa base.
# Ce n'est sans conséquence que si elles ont la même action : une règle
# spécifique ne partage sa priorité, sur une même ressource, qu'avec des règles
# de la même action. Les identifiants de ressource sont calculés, d'où l'apply.
run "tied_rules_share_their_action" {
  command = apply

  assert {
    condition = alltrue([
      for slot, actions in {
        for rule in local.declared_extra_rules :
        "${rule.resource_id}:${rule.priority}" => rule.action...
      } : length(distinct(actions)) == 1
    ])
    error_message = "Deux règles d'une même ressource à la même priorité ont des actions différentes : leur ordre, laissé à Pangolin, change le résultat."
  }

  # Le garde antislash est posé d'après une liste de noms
  # (local.backslash_guarded_resources) : ce sont les règles réellement
  # déclarées qui disent si elle est complète. Toute règle PATH d'une
  # ressource, quelle qu'elle soit, impose un DROP antislash sur cette
  # ressource.
  assert {
    condition = alltrue([
      for rule in local.declared_extra_rules :
      contains([for guard in pangolin_resource_rule.backslash_guard : guard.resource_id], rule.resource_id)
      if rule.match == "PATH"
    ])
    error_message = "Une règle par chemin vise une ressource sans DROP antislash : ajouter son nom à local.standalone_path_rule_resources (rules.tf)."
  }
}

run "grocy_mobile_header_auth_stays_narrow" {
  command = apply

  # Les identifiants Basic de l'appli Android passent le SSO de Grocy, et de
  # Grocy seulement ; extended_compatibility ferait répondre aux navigateurs
  # un défi Basic au lieu de la page de connexion (website_grocy.tf).
  assert {
    condition = (
      pangolin_resource_header_auth.grocy_mobile.resource_id == pangolin_resource.website["grocy"].id
      && pangolin_resource_header_auth.grocy_mobile.extended_compatibility == false
    )
    error_message = "L'authentification Basic de l'appli Grocy vise une autre ressource, ou remplace la page de connexion des navigateurs."
  }

  # L'appli lit `user:password@` dans l'URL du serveur et l'encode en
  # Base64.DEFAULT d'Android, qui coupe la ligne à 76 caractères : un mot de
  # passe alphanumérique, `user:password` sous 58 octets.
  assert {
    condition = (
      can(regex("^[A-Za-z0-9]+$", random_password.grocy_mobile.result))
      && length("${pangolin_resource_header_auth.grocy_mobile.user}:${random_password.grocy_mobile.result}") <= 57
    )
    error_message = "Les identifiants Basic de l'appli Grocy casseraient l'URL du serveur ou son en-tête Authorization."
  }
}

# Les clients sans session Pangolin (MCP de TREK, agents Beszel et de journaux
# des hôtes Hetzner) passent avec un jeton d'accès Pangolin, pas par un
# ACCEPT ; ceux du LAN n'en ont pas. Les sorties qui les portent ont le format
# que leur lecteur découpe, et les playbooks les lisent sous la clé
# inventory_hostname.
run "access_token_outputs_follow_their_reader" {
  command = apply

  # Un jeton d'accès passe le SSO de SA ressource : un bloc copié qui garde le
  # resource_id d'une autre ouvrirait celle-ci au client. Identifiants simulés
  # distincts (override_resource plus haut).
  assert {
    condition = alltrue(flatten([
      for family in [
        { website = "karakeep", tokens = values(pangolin_resource_access_token.karakeep_clients) },
        { website = "papra", tokens = values(pangolin_resource_access_token.papra_clients) },
        { website = "trek", tokens = values(pangolin_resource_access_token.trek_mcp_clients) },
        { website = "beszel", tokens = values(pangolin_resource_access_token.beszel_agents) },
        { website = "victoria_logs", tokens = values(pangolin_resource_access_token.log_agents) },
        ] : [
        for token in family.tokens : token.resource_id == pangolin_resource.website[family.website].id
      ]
    ]))
    error_message = "Un jeton d'accès client (Karakeep, Papra, MCP de TREK, agents Beszel ou de journaux) vise une autre ressource que la sienne."
  }

  # `?p_token=<id>.<jeton>` : Pangolin le découpe sur le point
  # (verifySession.ts) ; un autre séparateur et le jeton ne serait jamais lu.
  assert {
    condition = alltrue([
      for client in ["claude-ai", "claude-code"] :
      output.trek_mcp_client_access_tokens[client].connector_url == "https://travels.sylvain.cloud/mcp?p_token=tok-trek-mcp.jeton-trek-mcp"
      && output.trek_mcp_client_access_tokens[client].headers["P-Access-Token-Id"] == "tok-trek-mcp"
      && output.trek_mcp_client_access_tokens[client].headers["P-Access-Token"] == "jeton-trek-mcp"
    ])
    error_message = "L'URL de connecteur doit être https://<domaine>/mcp?p_token=<id>.<jeton>."
  }

  assert {
    condition = output.log_agent_access_tokens == {
      flip     = { id = "tok-log-agent", token = "jeton-log-agent" }
      pangolin = { id = "tok-log-agent", token = "jeton-log-agent" }
    }
    error_message = "log_agent_access_tokens doit donner à chaque agent distant (flip, pangolin) l'identifiant et le jeton de son accès Pangolin."
  }

  # HUB_HEADERS, au format « Nom: valeur » séparé par des virgules que lit
  # l'agent Beszel.
  assert {
    condition = output.beszel_agent_hub_headers == {
      flip     = "P-Access-Token-Id: tok-beszel-agent, P-Access-Token: jeton-beszel-agent"
      pangolin = "P-Access-Token-Id: tok-beszel-agent, P-Access-Token: jeton-beszel-agent"
    }
    error_message = "beszel_agent_hub_headers doit donner à chaque agent distant (flip, pangolin) ses en-têtes P-Access-Token-Id / P-Access-Token."
  }

  # Contrat Tofu <-> Ansible.
  assert {
    condition = alltrue([
      for playbook in ["flip.yml", "pangolin.yaml"] :
      strcontains(file("${path.module}/../../ansible/${playbook}"), "terraform_outputs.log_agent_access_tokens.value[inventory_hostname].id")
      && strcontains(file("${path.module}/../../ansible/${playbook}"), "terraform_outputs.log_agent_access_tokens.value[inventory_hostname].token")
      && strcontains(file("${path.module}/../../ansible/${playbook}"), "terraform_outputs.beszel_agent_hub_headers.value[inventory_hostname]")
    ])
    error_message = "flip.yml et pangolin.yaml doivent lire terraform_outputs.log_agent_access_tokens.value[inventory_hostname].id et .token, et terraform_outputs.beszel_agent_hub_headers.value[inventory_hostname]."
  }
}

# Chaque liste de local.path_bypasses a été relue dans les sources d'UNE
# version de l'image : quand elle monte, une nouvelle route non authentifiée
# sous un préfixe ouvert (ou un partage déplacé) changerait en silence ce qui
# répond au monde entier sans SSO. path_bypass_images.json note cette version.
# Renovate l'y monte en même temps que le compose (customManagers de
# renovate.json). La PR ne fusionne jamais seule (dernière règle de
# renovate.json) : sa note demande de relire les sources de `reread` avant le
# merge, fait à la main, sans commit de plus.
#
# Ce run garantit que le fichier dit vrai. Le tag seul est comparé :
# l'épinglage du digest ne compte pas.
run "path_bypasses_follow_their_image" {
  command = plan

  # Une montée faite à la main, dans le compose sans le fichier (ou
  # l'inverse), contournerait la relecture : la version notée doit être celle
  # que le compose déploie, sur chaque service qui tourne cette image (Dawarich
  # en a deux : un seul monté à la main passerait sinon).
  assert {
    condition = alltrue([
      for app, pin in jsondecode(file("${path.module}/path_bypass_images.json")) :
      (
        length(regexall("image: ${replace(pin.image, ".", "\\.")}:", file("${path.module}/../../${pin.compose}"))) >= 1 &&
        length(regexall("image: ${replace(pin.image, ".", "\\.")}:", file("${path.module}/../../${pin.compose}"))) == length(regexall(
          "image: ${replace(pin.image, ".", "\\.")}:${replace(pin.version, ".", "\\.")}(@|\\s)",
          file("${path.module}/../../${pin.compose}")
        ))
      )
    ])
    error_message = "Une image de path_bypass_images.json n'est pas à la version notée dans son compose : monter les deux ensemble (Renovate le fait), la relecture des sources de reread précède le merge."
  }

  # Toute ressource ouverte par chemin est gardée, ou écartée ici avec sa
  # raison : nos propres images (planning-equipes, promptoramix), dont les
  # chemins suivent le code que nous écrivons, et le banc Keycloak, qui ouvre
  # tout /auth/* (website_demo_planning_kc.tf) et n'a donc aucune route à
  # relire.
  assert {
    condition = setunion(
      keys(jsondecode(file("${path.module}/path_bypass_images.json"))),
      ["Demo Planning", "Demo Planning KC", "Flip Planning", "Promptoramix"],
    ) == toset(keys(local.path_bypasses))
    error_message = "Une ressource de local.path_bypasses n'a pas d'entrée dans path_bypass_images.json (ou une entrée n'y correspond à aucune) : sa version relue ne serait pas gardée."
  }

  # La note de PR de Renovate (dernière règle de renovate.json) renvoie à ces
  # champs : releases et reread disent quoi relire avant le merge.
  assert {
    condition = alltrue([
      for app, pin in jsondecode(file("${path.module}/path_bypass_images.json")) :
      alltrue([for k in ["image", "version", "compose", "paths", "reread", "releases"] : try(length(pin[k]) > 0, false)])
    ])
    error_message = "Chaque entrée de path_bypass_images.json porte image, version, compose, paths, reread et releases."
  }
}

# Verrouillage temporaire des applications PHP (php_lockdown.tf), le temps
# qu'une faille critique de PHP soit corrigée dans leurs images : aucune ne
# doit répondre sans le SSO, ni par sa ressource, ni par une ouverture par
# chemin active. À supprimer avec php_lockdown.tf quand le verrouillage est
# levé. Betisier et nextcloud n'y sont plus : leurs images sont corrigées.
run "php_lockdown_closes_every_public_php_path" {
  command = plan

  # Une faute de frappe dans les ensembles ne verrouillerait rien, sans un mot.
  assert {
    condition = (
      length(setsubtract(local.php_lockdown_sso, keys(local.websites))) == 0
      && length(setsubtract(local.php_lockdown_path_bypasses, keys(local.path_bypasses))) == 0
    )
    error_message = "php_lockdown.tf nomme une entrée absente de local.websites ou de local.path_bypasses."
  }

  # Ni l'inverse : les autres tests lisent l'état attendu dans ces mêmes
  # ensembles, une application qui n'est pas en PHP ajoutée par erreur y
  # perdrait son SSO-libre ou ses ouvertures par chemin sans qu'aucun ne
  # bronche. Tient aussi une fois les ensembles vidés.
  assert {
    condition = (
      length(setsubtract(local.php_lockdown_sso, ["betisier", "monica", "nextcloud", "rss", "wiki"])) == 0
      && length(setsubtract(local.php_lockdown_path_bypasses, ["Betisier", "Monica CRM", "nextcloud", "RSS", "Wiki (Bookstack)"])) == 0
    )
    error_message = "php_lockdown.tf nomme une application qui n'est pas en PHP."
  }

  # Monica, FreshRSS (rss) et BookStack (wiki). Leur SSO, lui, est tenu par
  # every_public_resource_applies_its_rules (seules Betisier et Promptoramix
  # s'en passent).
  assert {
    condition = length([
      for key, rule in pangolin_resource_rule.path_bypass : key
      if rule.enabled && anytrue([
        for name in ["Monica CRM", "RSS", "Wiki (Bookstack)"] :
        startswith(key, "${name} ")
      ])
    ]) == 0
    error_message = "Une ouverture par chemin active mène encore à une application PHP."
  }
}

# apply_rules = false laisse les règles pays en place mais Pangolin ne les
# évalue pas : NAS et Proxmox ont ainsi répondu de partout, derrière le seul
# SSO, pendant que rules.tf affichait leurs règles. Toute ressource publique
# applique donc les siennes, et seules Betisier, Promptoramix et la vitrine
# Exemple Planning se passent du SSO. Nextcloud l'a rejoint : ses clients et
# ses liens de partage passent par des chemins ouverts (website_nextcloud.tf),
# plus par une ressource entière sans SSO.
run "every_public_resource_applies_its_rules" {
  command = plan

  assert {
    condition     = alltrue([for r in pangolin_resource.website : r.apply_rules == true])
    error_message = "Une ressource publique a apply_rules = false : ses règles pays existent mais ne sont pas évaluées."
  }

  # Une ressource sans SSO n'a que son application pour la protéger. La liste
  # est fermée : en ajouter une est une décision, pas un oubli. Promptoramix y
  # est entrée par une décision explicite, validée par l'utilisateur : appelée
  # par les serveurs du tournoi Linkx (fonctions Supabase), pas par un
  # navigateur, elle ne peut pas passer de SSO et vérifie la signature HMAC de
  # chaque requête (website_promptoramix.tf). Exemple Planning aussi : la
  # vitrine publique de Planning Équipes, dont la page produit affiche le mot
  # de passe ; ce que cet admin partagé ne doit pas atteindre est coupé par ses
  # DROP (website_exemple_planning.tf, pinned plus bas).
  assert {
    condition = toset([for r in pangolin_resource.website : r.name if r.sso == false]) == setsubtract(
      toset(["Betisier", "Exemple Planning", "Promptoramix"]),
      [for key in local.php_lockdown_sso : local.websites[key].name],
    )
    error_message = "Les ressources sans SSO doivent être exactement Betisier, Exemple Planning et Promptoramix, moins celles que php_lockdown.tf remet derrière le SSO."
  }

  # Toutes les ressources publiques sont des instances de
  # pangolin_resource.website : aucune n'échappe aux épinglages, à la page de
  # maintenance ni à local.managed_resources, qui en est dérivée.
  assert {
    condition = (
      length(flatten([
        for f in fileset(path.module, "*.tf") :
        regexall("resource\\s+\"pangolin_resource\"\\s+\"", file("${path.module}/${f}"))
      ])) == 1
      && toset([for r in pangolin_resource.website : r.name]) == toset(keys(local.managed_resources))
    )
    error_message = "Une ressource Pangolin est déclarée hors de pangolin_resource.website (websites.tf), ou manque à local.managed_resources."
  }

  # local.websites liste à la main les entrées local.<app>_website des
  # website_*.tf : une entrée oubliée là ne créerait rien, sans un mot.
  assert {
    condition = toset(flatten([
      for f in fileset(path.module, "website_*.tf") :
      [for m in regexall("(?m)^  (\\w+)_website = \\{", file("${path.module}/${f}")) : m[0]]
    ])) == toset(keys(local.websites))
    error_message = "Une entrée local.<app>_website d'un website_*.tf manque à local.websites (websites.tf), ou l'inverse."
  }
}

# Les attributs optionnels+calculés de pangolin_resource sont épinglés sur
# chaque ressource (resource_defaults.tf). Non déclaré, un attribut accepte ce
# que l'API renvoie et le plan ne voit plus rien ; `mode`, lui, force un
# remplacement : un changement de son défaut côté provider recréerait toutes
# les ressources qui s'y fient.
run "every_resource_declares_the_pinned_attributes" {
  command = plan

  # Aucune dérogation, sauf `enabled`, qu'une entrée de local.websites peut
  # surcharger pour mettre l'app en pause (websites.tf).
  assert {
    condition = alltrue([
      for key, r in pangolin_resource.website :
      r.mode == local.resource_pins.mode
      && r.ssl == local.resource_pins.ssl
      && r.enabled == lookup(local.websites[key], "enabled", local.resource_pins.enabled)
      && r.block_access == local.resource_pins.block_access
      && r.email_whitelist_enabled == local.resource_pins.email_whitelist_enabled
      && r.sticky_session == local.resource_pins.sticky_session
    ])
    error_message = "Une ressource Pangolin ne suit pas local.resource_pins (mode, ssl, enabled...)."
  }

  # Les apps en pause, en toutes lettres (docs/runbooks/app-en-pause.md) : en
  # mettre une en pause ou la reprendre est une décision, pas un effet de bord.
  assert {
    condition     = [for key, r in pangolin_resource.website : key if !r.enabled] == ["demo_planning_kc", "paperless"]
    error_message = "Les apps en pause (enabled = false) ont changé : relire docs/runbooks/app-en-pause.md, puis cette liste."
  }

  # L'interrupteur Ansible bouge avec celui de Tofu : une ressource reprise
  # sur une app encore arrêtée ferait sonner ses moniteurs, une app reprise
  # derrière une ressource désactivée sauvegarderait sans moniteur actif.
  assert {
    condition = lookup(
      yamldecode(file("${path.module}/../../ansible/host_vars/docker/variables.yaml")),
      "paperless_enabled", true
    ) == pangolin_resource.website["paperless"].enabled
    error_message = "paperless_enabled (ansible/host_vars/docker/variables.yaml) et enabled de l'entrée paperless (website_paperless.tf) doivent être égaux."
  }

  # Même chose pour le banc Keycloak, dont l'interrupteur est un paramètre de
  # rôle de son entrée de flip.yml (le rôle y est appliqué trois fois).
  assert {
    condition = [
      for entry in yamldecode(file("${path.module}/../../ansible/flip.yml"))[0].roles :
      lookup(entry.vars, "flip_planning_enabled", true)
      if entry.role == "flip_planning" && try(entry.vars.flip_planning_service, "") == "demo_planning_kc"
    ] == [pangolin_resource.website["demo_planning_kc"].enabled]
    error_message = "flip_planning_enabled de l'entrée demo_planning_kc d'ansible/flip.yml et enabled de l'entrée demo_planning_kc (website_demo_planning_kc.tf) doivent être égaux."
  }
}

# Deux ressources sur le même FQDN se marcheraient dessus dans Traefik.
run "resources_have_unique_fqdns" {
  command = plan

  assert {
    condition = length(distinct([
      for r in pangolin_resource.website : "${r.subdomain == null ? "@" : r.subdomain}.${r.domain_id}"
    ])) == length(local.managed_resources)
    error_message = "Deux ressources Pangolin partagent le même sous-domaine sur le même domaine."
  }
}

# Page de maintenance automatique partout (jamais `forced`, qui masquerait un
# site sain), et moniteurs à mot-clé inversé sur le titre de cette page : elle
# répond 200, donc seul le mot-clé distingue un service tombé.
run "maintenance_page_and_inverted_keyword_monitors" {
  command = plan

  assert {
    condition = local.maintenance.type == "automatic" && alltrue([
      for r in pangolin_resource.website :
      r.maintenance_mode_enabled == local.maintenance.enabled
      && r.maintenance_mode_type == local.maintenance.type
      && r.maintenance_title == local.maintenance.title
      && r.maintenance_message == local.maintenance.message
    ])
    error_message = "Chaque ressource doit servir la page de maintenance de local.maintenance (maintenance.tf), en mode automatic."
  }

  # Un healthcheck par application, sauf le banc KC (healthcheck = false) :
  # une application ajoutée l'a d'office, en retirer un est une décision.
  assert {
    condition     = toset(keys(uptimekuma_monitor_http_keyword.healthcheck)) == setsubtract(toset(keys(local.websites)), ["demo_planning_kc"])
    error_message = "Chaque application a son healthcheck, sauf demo_planning_kc."
  }

  assert {
    condition = alltrue([
      for m in uptimekuma_monitor_http_keyword.healthcheck :
      m.invert_keyword == true
      && m.keyword == pangolin_resource.website["flip_planning"].maintenance_title
    ])
    error_message = "Chaque healthcheck doit chercher le titre de la page de maintenance en mot-clé inversé : sinon la page (HTTP 200) passe pour un service sain."
  }

  # Un healthcheck actif sur une ressource désactivée ne pourrait qu'être DOWN
  # et écrire : chaque healthcheck suit l'état de sa ressource.
  assert {
    condition = alltrue([
      for key, m in uptimekuma_monitor_http_keyword.healthcheck :
      m.active == pangolin_resource.website[key].enabled
    ])
    error_message = "Un healthcheck doit suivre l'état (enabled) de sa ressource."
  }
}

# L'URL du moniteur du dashboard Pangolin est celle que publie le rôle
# pangolin (host_vars/pangolin) : un renommage d'un seul côté laisserait le
# moniteur sonder un nom mort. Pas de mot-clé inversé ici : le dashboard n'est
# pas une ressource Pangolin, donc pas de page de maintenance à reconnaître.
run "pangolin_dashboard_monitor_follows_host_vars" {
  command = plan

  assert {
    condition = (
      uptimekuma_monitor_http.pangolin_dashboard.url == "https://pangolin.sylvain.cloud"
      && uptimekuma_monitor_http.pangolin_dashboard.active == true
      && strcontains(
        file("${path.module}/../../ansible/host_vars/pangolin/variables.yaml"),
        "\npangolin_base_domain: \"sylvain.cloud\"\n"
      )
      && strcontains(
        file("${path.module}/../../ansible/host_vars/pangolin/variables.yaml"),
        "\npangolin_dashboard_url: \"pangolin.{{ pangolin_base_domain }}\"\n"
      )
    )
    error_message = "Le moniteur du dashboard doit sonder pangolin_dashboard_url (ansible/host_vars/pangolin/variables.yaml), soit https://pangolin.sylvain.cloud."
  }
}

# Un rôle Pangolin par slug de roles.tf, nommé comme lui, et un par
# environnement de Flip Planning.
run "one_role_per_app_slug" {
  command = plan

  assert {
    condition     = alltrue([for slug, role in pangolin_role.apps : role.name == slug])
    error_message = "Chaque rôle de pangolin_role.apps doit porter le nom de son slug."
  }

  assert {
    condition = alltrue([
      for slug in ["flip-planning", "demo-planning", "demo-planning-kc"] :
      contains(keys(pangolin_role.apps), slug)
    ])
    error_message = "Chaque environnement de Flip Planning a son propre rôle : un rôle partagé ouvrirait la production aux testeurs de la démo."
  }

  # Un rôle qu'aucun pangolin_resource_role ne lie n'ouvre rien et encombre la
  # liste des rôles (betisier et meerkat l'ont fait). Dans l'autre sens, une
  # entrée de local.websites qui nomme un rôle absent de roles.tf ferait
  # échouer le plan sur pangolin_role.apps[...].
  assert {
    condition = (
      toset(keys(pangolin_role.apps))
      == toset([for website in values(local.websites) : lookup(website, "role", null) if lookup(website, "role", null) != null])
    )
    error_message = "Un slug de roles.tf n'est lié à aucune ressource par une entrée de local.websites (champ role), ou l'inverse : le retirer, ou le lier."
  }

  # Une liaison par entrée qui nomme un rôle : toutes les applications sauf
  # Betisier, Exemple Planning et Promptoramix (sans SSO).
  assert {
    condition     = setsubtract(toset(keys(local.websites)), keys(pangolin_resource_role.website)) == toset(["betisier", "exemple_planning", "promptoramix"])
    error_message = "Chaque application derrière le SSO est liée à son rôle ; Betisier, Exemple Planning et Promptoramix, sans SSO, à aucun."
  }

  # Chaque entrée prend le rôle de son propre slug (sa clé en kebab-case) : un
  # rôle emprunté ouvre l'application aux membres d'une autre (la production de
  # Flip Planning aux testeurs de la démo). Seule dérogation, décidée : Immich
  # Swipe, qui agit sur la photothèque d'Immich, prend le rôle d'Immich.
  assert {
    condition = alltrue([
      for key, website in local.websites :
      lookup(website, "role", null) == null || website.role == lookup({ immich_swipe = "immich" }, key, replace(key, "_", "-"))
    ])
    error_message = "Une entrée de local.websites emprunte le rôle d'une autre application (seul immich_swipe prend celui d'Immich)."
  }
}

# ===========================================================================
# Runs `apply` : valeurs calculées (identifiants, jetons, FQDN)
# ===========================================================================

# La clé de local.managed_resources EST le nom Pangolin de la ressource : c'est
# ce que l'audit de couverture compare à l'API. Une clé décalée (ou pointant
# sur la mauvaise ressource) laisserait une application sans filtre pays tout
# en passant l'audit.
run "country_rules_attach_to_the_resource_named_by_their_key" {
  command = apply

  # Compte les ressources qui passent plutôt qu'un alltrue : une ressource
  # sans ses règles fait aussi échouer le run.
  assert {
    condition = length([
      for r in pangolin_resource.website :
      r.name if try(
        pangolin_resource_rule.block_country[r.name].resource_id == r.id
        && pangolin_resource_rule.allow_countries["${r.name}-FR"].resource_id == r.id
        && pangolin_resource_rule.allow_countries["${r.name}-DE"].resource_id == r.id,
        false
      )
    ]) == length(local.managed_resources)
    error_message = "Une entrée de local.managed_resources ne porte pas le nom exact de la ressource vers laquelle elle pointe (ou la ressource manque à la liste de ce run)."
  }

  # Garde-fou du test lui-même : sans identifiants distincts, l'égalité
  # ci-dessus serait vraie par construction.
  assert {
    condition     = length(distinct([for rule in pangolin_resource_rule.block_country : rule.resource_id])) == length(local.managed_resources)
    error_message = "Les identifiants simulés des ressources doivent être distincts pour que ce run prouve quelque chose."
  }

  # Chaque ouverture par chemin et chaque garde antislash vise la ressource
  # dont le nom préfixe sa clé ; les règles autonomes, celle de leur fichier.
  assert {
    condition = alltrue(concat(
      flatten([
        for name, paths in local.path_bypasses : [
          for path in keys(paths) :
          pangolin_resource_rule.path_bypass["${name} ${path}"].resource_id == one([for r in pangolin_resource.website : r.id if r.name == name])
        ]
      ]),
      [
        for name, rule in pangolin_resource_rule.backslash_guard :
        rule.resource_id == one([for r in pangolin_resource.website : r.id if r.name == name])
      ],
      [
        pangolin_resource_rule.immich_home_ip.resource_id == pangolin_resource.website["immich"].id,
        pangolin_resource_rule.dawarich_home_ip.resource_id == pangolin_resource.website["dawarich"].id,
        pangolin_resource_rule.trek_home_ip.resource_id == pangolin_resource.website["trek"].id,
        pangolin_resource_rule.trek_mcp.resource_id == pangolin_resource.website["trek"].id,
        pangolin_resource_rule.beszel_agent_connect.resource_id == pangolin_resource.website["beszel"].id,
        pangolin_resource_rule.victoria_logs_insert.resource_id == pangolin_resource.website["victoria_logs"].id,
      ],
    ))
    error_message = "Une règle spécifique est rattachée à la mauvaise ressource."
  }
}

# Les sorties lues par les playbooks (`terraform_outputs.<nom>.value |
# default('')`) : une sortie renommée ou supprimée donne une chaîne vide sans
# erreur, et la sauvegarde ne signale plus jamais rien. Chacune doit exister et
# pointer sur le jeton de SON moniteur push.
run "outputs_read_by_ansible_point_at_their_own_push_monitor" {
  command = apply

  # Chaque sortie => le jeton push simulé de SON moniteur (override_resource
  # plus haut). Deux playbooks qui poussent sur le même moniteur se masquent
  # l'un l'autre : les URL sont distinctes, et autant que de sorties
  # uptime_*_url dans le module, si bien qu'une sortie ajoutée sans être
  # listée ici fait aussi échouer le run.
  assert {
    condition = alltrue([
      for urls in [{
        # docker.yml
        uptime_backup_nextcloud_url         = output.uptime_backup_nextcloud_url
        uptime_backup_wiki_url              = output.uptime_backup_wiki_url
        uptime_backup_rss_url               = output.uptime_backup_rss_url
        uptime_backup_monica_url            = output.uptime_backup_monica_url
        uptime_cron_monica_url              = output.uptime_cron_monica_url
        uptime_backup_betisier_url          = output.uptime_backup_betisier_url
        uptime_cron_betisier_reset_url      = output.uptime_cron_betisier_reset_url
        uptime_backup_dawarich_url          = output.uptime_backup_dawarich_url
        uptime_backup_trek_url              = output.uptime_backup_trek_url
        uptime_backup_karakeep_url          = output.uptime_backup_karakeep_url
        uptime_backup_homebox_url           = output.uptime_backup_homebox_url
        uptime_backup_speedtest_tracker_url = output.uptime_backup_speedtest_tracker_url
        uptime_backup_ntfy_url              = output.uptime_backup_ntfy_url
        uptime_backup_wishlist_url          = output.uptime_backup_wishlist_url
        uptime_backup_beszel_url            = output.uptime_backup_beszel_url
        uptime_backup_paperless_url         = output.uptime_backup_paperless_url
        uptime_backup_papra_url             = output.uptime_backup_papra_url
        uptime_backup_grocy_url             = output.uptime_backup_grocy_url
        uptime_cron_ntfy_subscribers_url    = output.uptime_cron_ntfy_subscribers_url
        # flip.yml (production, démo, vitrine)
        uptime_backup_flip_planning_url        = output.uptime_backup_flip_planning_url
        uptime_backup_demo_planning_url        = output.uptime_backup_demo_planning_url
        uptime_cron_exemple_planning_reset_url = output.uptime_cron_exemple_planning_reset_url
        # pi.yml, lxc.yml
        uptime_backup_immich_url = output.uptime_backup_immich_url
        uptime_cron_dns_pi_url   = output.uptime_cron_dns_pi_url
        uptime_cron_dns_lxc_url  = output.uptime_cron_dns_lxc_url
        # pangolin.yaml
        uptime_backup_pangolin_url = output.uptime_backup_pangolin_url
        uptime_cron_geoip_url      = output.uptime_cron_geoip_url
        # nas.yml
        uptime_backup_jellyfin_url  = output.uptime_backup_jellyfin_url
        uptime_cron_nas_cert_url    = output.uptime_cron_nas_cert_url
        uptime_cron_kdrive_sync_url = output.uptime_cron_kdrive_sync_url
        # pve.yml
        uptime_cron_vzdump_restore_test_url = output.uptime_cron_vzdump_restore_test_url
        uptime_cron_pve_updates_url         = output.uptime_cron_pve_updates_url
        # update_notify : docker.yml, pi.yml, flip.yml, pangolin.yaml
        uptime_cron_docker_updates_url   = output.uptime_cron_docker_updates_url
        uptime_cron_pi_updates_url       = output.uptime_cron_pi_updates_url
        uptime_cron_flip_updates_url     = output.uptime_cron_flip_updates_url
        uptime_cron_pangolin_updates_url = output.uptime_cron_pangolin_updates_url
        }] : alltrue([
        for name, url in urls :
        url == "https://uptime.example.test/api/push/push-${replace(trimsuffix(trimprefix(trimprefix(name, "uptime_"), "backup_"), "_url"), "_", "-")}"
        ]) && length(distinct(values(urls))) == length(flatten([
          for f in fileset(path.module, "*.tf") :
          regexall("output \"uptime_(?:backup|cron)_\\w+_url\"", file("${path.module}/${f}"))
      ]))
    ])
    error_message = "Une sortie uptime_*_url lue par Ansible ne pointe pas sur le jeton de SON moniteur push (push-<nom de la sortie>), deux pointent sur le même, ou une sortie manque à cette liste."
  }

  # Dans l'autre sens : un moniteur push dont aucun playbook ne lit l'URL ne
  # reçoit jamais de battement et reste rouge (searxng et paperless jusqu'à
  # leur ajout dans docker.yml, echo qui n'a pas de sauvegarde).
  assert {
    condition = alltrue([
      for name in flatten([
        for f in fileset(path.module, "*.tf") :
        regexall("output \"(uptime_(?:backup|cron)_\\w+_url)\"", file("${path.module}/${f}"))
      ]) :
      anytrue([
        for playbook in ["docker.yml", "flip.yml", "lxc.yml", "nas.yml", "pi.yml", "pangolin.yaml", "pve.yml"] :
        strcontains(file("${path.module}/../../ansible/${playbook}"), "terraform_outputs.${name}.value")
      ])
    ]) && output.uptime_backup_trek_url != ""
    error_message = "Une sortie uptime_*_url n'est lue par aucun playbook : son moniteur push ne recevra jamais rien."
  }
}

# flip.yml lit les identifiants Newt du site flip dans ce state (et échoue
# s'ils sont vides) : ils doivent venir de pangolin_site.flip, pas d'un autre
# site dont le Newt se connecterait à la place.
run "flip_newt_credentials_come_from_the_flip_site" {
  command = apply

  assert {
    condition     = output.flip_newt_id == "newt-flip" && output.flip_newt_secret == "secret-flip"
    error_message = "flip_newt_id / flip_newt_secret doivent être ceux de pangolin_site.flip."
  }

  # lxc.yml lit ceux du LXC de la même façon.
  assert {
    condition     = output.proxmox_lxc_newt_id == "newt-proxmox-lxc" && output.proxmox_lxc_newt_secret == "secret-proxmox-lxc"
    error_message = "proxmox_lxc_newt_id / proxmox_lxc_newt_secret doivent être ceux de pangolin_site.proxmox_lxc."
  }

  assert {
    condition     = pangolin_site.flip.docker_socket_enabled == true
    error_message = "Le Newt de flip lit le socket Docker pour joindre les conteneurs de Flip Planning."
  }

  # flip.internal : SSH manuel uniquement, servi par le Newt de flip vers l'IP
  # privée lue dans le state de tofu/pangolin.
  assert {
    condition = (
      pangolin_site_resource.flip.site_id == pangolin_site.flip.id
      && pangolin_site_resource.flip.destination == "10.0.1.10"
      && pangolin_site_resource.flip.alias == "flip.internal"
      && pangolin_site_resource.flip.mode == "host"
      && pangolin_site_resource.flip.tcp_port_range == "22"
      && pangolin_site_resource.flip.udp_port_range == "*"
    )
    error_message = "flip.internal doit viser l'IP privée de flip (remote state), sur le site flip, en TCP 22 (UDP à \"*\" : le provider ne sait pas envoyer une plage vide, ufw sur flip ne laisse entrer que 22/tcp)."
  }
}

# Le Blocky du LXC newt (lxc.yml, rôle blocky en binaire), pour un téléphone
# en 4G par le client Pangolin : la ressource vise l'IP du LXC de l'inventaire,
# sur le site du LXC lui-même, en TCP et UDP 53 seulement.
run "dns_resource_points_at_the_lxc_blocky" {
  command = plan

  assert {
    condition = (
      pangolin_site_resource.dns.site_id == pangolin_site.proxmox_lxc.id
      && pangolin_site_resource.dns.mode == "host"
      && pangolin_site_resource.dns.destination == "192.168.1.200"
      && strcontains(file("${path.module}/../../ansible/inventory/hosts"), "newt-lxc ansible_host=192.168.1.200 ")
      && pangolin_site_resource.dns.tcp_port_range == "53"
      && pangolin_site_resource.dns.udp_port_range == "53"
      && strcontains(file("${path.module}/../../ansible/lxc.yml"), "- role: blocky\n")
    )
    error_message = "La ressource dns doit viser le LXC newt de ansible/inventory/hosts (site proxmox-lxc), en TCP et UDP 53, et lxc.yml y déployer Blocky."
  }

  # Les noms fixes de Blocky (blocky_custom_dns) suivent les IP de
  # l'inventaire et de la VM docker (tofu/proxmox) ; les noms publics qui
  # pointent dans le LAN (A de tofu/dns vers le NAS) passent la protection
  # contre le rebinding, sinon ils ne résolvent plus à la maison.
  assert {
    condition = (
      yamldecode(file("${path.module}/../../ansible/roles/blocky/defaults/main.yml")).blocky_custom_dns == {
        "pve.lan"      = "192.168.1.26"
        "docker.lan"   = "192.168.1.216"
        "nas.lan"      = "192.168.1.137"
        "newt-lxc.lan" = "192.168.1.200"
      }
      && strcontains(file("${path.module}/../../ansible/inventory/hosts"), "pve ansible_host=192.168.1.26\n")
      && strcontains(file("${path.module}/../../ansible/inventory/hosts"), "nas ansible_host=192.168.1.137 ")
      && strcontains(file("${path.module}/../proxmox/proxmox_docker_vm.tf"), "address = \"192.168.1.216/24\"")
      && toset(yamldecode(file("${path.module}/../../ansible/roles/blocky/defaults/main.yml")).blocky_rebinding_allowed_domains) == toset([
        for f in fileset("${path.module}/../dns", "*.tf") : "${trimsuffix(f, ".tf")}.sylvain.cloud"
        if can(regex("(?m)^\\s*target\\s*=\\s*\"192\\.168\\.", file("${path.module}/../dns/${f}")))
      ])
    )
    error_message = "blocky_custom_dns doit suivre les IP de ansible/inventory/hosts et de tofu/proxmox, et blocky_rebinding_allowed_domains lister chaque A de tofu/dns vers une IP du LAN (fichier <sous-domaine>.tf)."
  }
}

# nas.yml lit les identifiants Newt du site nas dans ce state (et échoue s'ils
# sont vides), sous leur forme littérale : une sortie renommée donnerait un
# Newt sans identifiants.
run "nas_newt_credentials_and_media" {
  command = apply

  assert {
    condition = (
      output.nas_newt_id == "newt-nas" && output.nas_newt_secret == "secret-nas"
      && strcontains(file("${path.module}/../../ansible/nas.yml"), "terraform_outputs.nas_newt_id.value | default('')")
      && strcontains(file("${path.module}/../../ansible/nas.yml"), "terraform_outputs.nas_newt_secret.value | default('')")
    )
    error_message = "nas_newt_id / nas_newt_secret doivent être ceux de pangolin_site.nas, lus tels quels par ansible/nas.yml."
  }

  # Le Newt du NAS joint le Traefik du NAS (rôle nas_proxy) par son nom de
  # conteneur sur le réseau newt (nas_proxy_container_name, container_name de
  # son compose), en TCP 443 et 8443 (nas_proxy_https_port, l'entrée LAN de
  # Traefik) seulement : Jellyfin lui-même (8096) n'est plus joignable par
  # Pangolin. L'alias est le nom public dont le A vise l'IP LAN du NAS
  # (tofu/dns), pour une seule URL en LAN et dehors.
  assert {
    condition = (
      pangolin_site_resource.jellyfin.site_id == pangolin_site.nas.id
      && pangolin_site_resource.jellyfin.mode == "host"
      && pangolin_site_resource.jellyfin.alias == "media.sylvain.cloud"
      && strcontains(file("${path.module}/../dns/media.tf"), "subdomain = \"media\"")
      && pangolin_site_resource.jellyfin.destination == "nas-proxy"
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml"), "\nnas_proxy_container_name: nas-proxy\n")
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/templates/compose.yaml"), "container_name: {{ nas_proxy_container_name }}\n")
      && pangolin_site_resource.jellyfin.tcp_port_range == "443,8443"
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml"), "\nnas_proxy_https_port: 8443\n")
      && pangolin_site_resource.jellyfin.udp_port_range == "*"
      && pangolin_site_resource.jellyfin.disable_icmp == true
    )
    error_message = "media.sylvain.cloud doit viser le conteneur nas-proxy (nas_proxy_container_name), sur le site nas, en TCP 443 et 8443 (nas_proxy_https_port) seuls, ICMP coupé."
  }

  # Une ressource privée, jamais publique, ouverte au seul rôle jellyfin.
  assert {
    condition = (
      pangolin_site_resource_role.jellyfin.site_resource_id == pangolin_site_resource.jellyfin.id
      && pangolin_site_resource_role.jellyfin.role_id == pangolin_role.jellyfin.id
      && pangolin_role.jellyfin.name == "jellyfin"
      && !contains(keys(local.websites), "jellyfin")
    )
    error_message = "media.sylvain.cloud doit être ouverte au rôle jellyfin, et Jellyfin n'avoir aucune ressource publique."
  }

  # ansible/pc-nas.yml monte un partage SMB du NAS (IP de l'entrée nas de
  # l'inventaire) : client Pangolin connecté, ce montage passe par la ressource
  # nas, qui doit viser la même IP et laisser passer TCP 445 en plus de l'UI :
  # 443 (relais du Traefik du NAS, nas_proxy_host_https_port), 8443 (Traefik
  # du NAS, nas_proxy_https_port) et 9999 (secours en HTTP).
  # L'alias est le nom public dont le A (tofu/dns/nas.tf) vise cette IP, et
  # que sert le routeur ugos de Traefik.
  assert {
    condition = (
      pangolin_site_resource.nas.destination == "192.168.1.137"
      && strcontains(file("${path.module}/../../ansible/inventory/hosts"), "nas ansible_host=192.168.1.137 ")
      && strcontains(file("${path.module}/../../ansible/pc-nas.yml"), "hostvars['nas'].ansible_host")
      && pangolin_site_resource.nas.tcp_port_range == "443,445,8443,9999"
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml"), "\nnas_proxy_host_https_port: 443\n")
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml"), "\nnas_proxy_https_port: 8443\n")
      && pangolin_site_resource.nas.alias == "nas.sylvain.cloud"
      && strcontains(file("${path.module}/../dns/nas.tf"), "subdomain = \"nas\"")
      && strcontains(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml"), "\nnas_proxy_ugos_domain: nas.sylvain.cloud\n")
    )
    error_message = "La ressource nas doit viser l'IP du NAS de ansible/inventory/hosts, lue par ansible/pc-nas.yml, sous l'alias nas.sylvain.cloud (tofu/dns/nas.tf, nas_proxy_ugos_domain), en TCP 443 et 8443 (Traefik du NAS), 445 (SMB) et 9999 (UI en HTTP)."
  }
}

# Une mise à jour de pangolin_site_resource efface ses rôles, utilisateurs et
# clients (le provider 1.6.1 envoie des listes vides) : chaque liaison, d'hier
# ou à venir, dans n'importe quel fichier du module, est recréée par
# replace_triggered_by sur la ressource qu'elle lie. Le lifecycle n'est pas
# lisible depuis un test : lu dans le source, lignes commentées exclues (ancrage
# en début de ligne). Jamais create_before_destroy : la nouvelle liaison, en
# tout point identique à l'ancienne, serait ajoutée (refusée, déjà présente)
# avant que la suppression de l'ancienne ne la retire.
run "site_resource_bindings_follow_their_resource" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for f in fileset(path.module, "*.tf") : [
        for body in regexall("(?ms)^resource\\s+\"pangolin_site_resource_(?:role|user|client)\"\\s+\"\\w+\"\\s+\\{(.*?)\\n\\}", file("${path.module}/${f}")) :
        length(regexall("(?m)^\\s*site_resource_id\\s*=\\s*pangolin_site_resource\\.\\w+\\.id\\s*$", body[0])) == 1
        && alltrue([
          for target in regexall("(?m)^\\s*site_resource_id\\s*=\\s*pangolin_site_resource\\.(\\w+)\\.id\\s*$", body[0]) :
          length(regexall("(?m)^\\s*replace_triggered_by\\s*=\\s*\\[[^\\]]*\\bpangolin_site_resource\\.${target[0]}\\s*[,\\]]", body[0])) == 1
        ])
        && length(regexall("(?m)^\\s*create_before_destroy\\s*=\\s*true", body[0])) == 0
      ]
      ])) && length(flatten([
      for f in fileset(path.module, "*.tf") :
      regexall("(?m)^resource\\s+\"pangolin_site_resource_(?:role|user|client)\"\\s+\"", file("${path.module}/${f}"))
    ])) >= 3
    error_message = "Une pangolin_site_resource_{role,user,client} n'a pas lifecycle { replace_triggered_by = [pangolin_site_resource.<ressource liée>] } (ou ne lie pas une pangolin_site_resource par site_resource_id = pangolin_site_resource.<x>.id, ou porte create_before_destroy) : la prochaine mise à jour de la ressource l'effacerait de Pangolin en la laissant dans le state."
  }
}

# Production et démo partagent un rôle Ansible mais rien côté Pangolin /
# Uptime Kuma : ressource, jeton d'accès, healthcheck et cibles sont
# distincts (les moniteurs de sauvegarde le sont par
# outputs_read_by_ansible_point_at_their_own_push_monitor, le SSO par
# every_public_resource_applies_its_rules), et chaque cible vise les conteneurs de
# son instance (préfixe flip_planning_container_prefix) sur le site flip.
run "demo_and_production_planning_share_nothing" {
  command = apply

  assert {
    condition = (
      pangolin_resource_access_token.healthcheck["flip_planning"].resource_id == pangolin_resource.website["flip_planning"].id
      && pangolin_resource_access_token.healthcheck["demo_planning"].resource_id == pangolin_resource.website["demo_planning"].id
      && pangolin_resource_access_token.healthcheck["flip_planning"].token != pangolin_resource_access_token.healthcheck["demo_planning"].token
    )
    error_message = "Chaque environnement doit avoir son propre jeton d'accès, rattaché à sa propre ressource."
  }

  assert {
    condition = (
      jsondecode(uptimekuma_monitor_http_keyword.healthcheck["flip_planning"].headers)["P-Access-Token-Id"] == "tok-flip-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.healthcheck["flip_planning"].headers)["P-Access-Token"] == "jeton-flip-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.healthcheck["demo_planning"].headers)["P-Access-Token-Id"] == "tok-demo-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.healthcheck["demo_planning"].headers)["P-Access-Token"] == "jeton-demo-planning"
    )
    error_message = "Chaque healthcheck doit s'authentifier avec le jeton de SON environnement."
  }

  assert {
    condition = (
      jsondecode(output.flip_planning_access_token).token == "jeton-flip-planning"
      && jsondecode(output.demo_planning_access_token).token == "jeton-demo-planning"
    )
    error_message = "Les sorties *_access_token doivent exposer le jeton de leur propre environnement."
  }

  # Les cibles de Flip Planning (production et démos) sont sur le site flip.
  # Leur rattachement à la ressource, lui, est l'expression même de
  # websites.tf : le recalculer ici ne prouverait rien ; les rôles, distincts
  # par environnement, sont tenus par one_role_per_app_slug.
  assert {
    condition = alltrue([
      for key, t in pangolin_target.website :
      t.site_id == pangolin_site.flip.id
      if contains(["flip_planning", "demo_planning", "demo_planning_kc"], local.website_targets[key].website)
    ])
    error_message = "Une cible de Flip Planning n'est pas sur le site flip."
  }

  assert {
    condition = (
      toset([
        pangolin_target.website["flip_planning"].ip,
        pangolin_target.website["flip_planning_pgadmin"].ip,
        pangolin_target.website["flip_planning_mailpit"].ip,
        pangolin_target.website["flip_planning_assets"].ip,
        ]) == toset([
        "flip-planning", "flip-planning-pgadmin", "flip-planning-mailpit", "flip-planning-assets",
      ])
      && toset([
        pangolin_target.website["demo_planning"].ip,
        pangolin_target.website["demo_planning_pgadmin"].ip,
        pangolin_target.website["demo_planning_mailpit"].ip,
        pangolin_target.website["demo_planning_assets"].ip,
        ]) == toset([
        "demo-planning", "demo-planning-pgadmin", "demo-planning-mailpit", "demo-planning-assets",
      ])
    )
    error_message = "Une cible vise un conteneur de l'autre instance : les noms doivent suivre flip_planning_container_prefix de chaque environnement."
  }
}

# Rangement et alerting des moniteurs : chaque sauvegarde dans le dossier
# Backup avec une fenêtre de 25 h (sauvegarde quotidienne, plus l'heure
# du changement d'heure d'octobre), chaque healthcheck dans Self-hosted, et
# tous reliés à Telegram et ntfy (un moniteur sans notification ne prévient
# personne, comme gramps et scanopy en 503 pendant des heures). Tout moniteur
# de sauvegarde est actif.
run "monitors_are_filed_and_alert" {
  command = apply

  # Les moniteurs de sauvegarde sont les instances de
  # uptimekuma_monitor_push.backup (entrées `backup = true` de local.websites),
  # plus ceux de Pangolin et de Jellyfin (NAS) ; leur liste est tenue par
  # .github/restore-test/apps.json, plus bas.
  assert {
    condition = alltrue([
      for m in concat(values(uptimekuma_monitor_push.backup), [uptimekuma_monitor_push.backup_pangolin, uptimekuma_monitor_push.backup_jellyfin]) :
      m.parent == uptimekuma_monitor_group.backups.id
      && m.interval == 25 * 3600
      && toset(m.notification_ids) == toset(local.alert_notification_ids)
    ])
    error_message = "Chaque moniteur de sauvegarde doit être dans le dossier Backup, à 25 h (le changement d'heure d'octobre espace deux sauvegardes de 25 h) et notifié sur Telegram et ntfy."
  }

  # Actif tant que l'app tourne : une app en pause (enabled = false) n'a plus
  # de configuration borgmatic, donc plus de push à attendre.
  assert {
    condition = uptimekuma_monitor_push.backup_pangolin.active == true && alltrue([
      for key, m in uptimekuma_monitor_push.backup :
      m.active == pangolin_resource.website[key].enabled
    ])
    error_message = "Un moniteur de sauvegarde doit être actif exactement quand son app l'est (Pangolin toujours)."
  }

  # Test de restauration du 1er et du 15 (.github/workflows/restore-test.yaml,
  # restore_test_monitor.tf) : un seul moniteur, rangé avec les sauvegardes,
  # à 20 jours (17 au plus entre deux runs ; le provider plafonne à 24).
  assert {
    condition = (
      uptimekuma_monitor_push.restore_test.parent == uptimekuma_monitor_group.backups.id
      && uptimekuma_monitor_push.restore_test.interval == 20 * 86400
      && uptimekuma_monitor_push.restore_test.active == true
      && toset(uptimekuma_monitor_push.restore_test.notification_ids) == toset(local.alert_notification_ids)
    )
    error_message = "Le moniteur Restore test doit être dans le dossier Backup, à 20 jours, actif et notifié sur Telegram et ntfy."
  }

  # Remplissage de la Storage Box, chaque lundi
  # (.github/workflows/storage-box-quota.yaml) : un run par semaine, plus un
  # jour de marge, sous le plafond de 24 jours du provider.
  assert {
    condition = (
      uptimekuma_monitor_push.storage_box_quota.parent == uptimekuma_monitor_group.backups.id
      && uptimekuma_monitor_push.storage_box_quota.interval > 7 * 86400
      && uptimekuma_monitor_push.storage_box_quota.interval < 24 * 86400
      && uptimekuma_monitor_push.storage_box_quota.active == true
      && toset(uptimekuma_monitor_push.storage_box_quota.notification_ids) == toset(local.alert_notification_ids)
      && strcontains(file("${path.module}/../../.github/workflows/storage-box-quota.yaml"), "- cron: \"0 6 * * 1\"")
    )
    error_message = "Le moniteur Storage Box doit être dans le dossier Backup, entre une semaine et 24 jours, actif et notifié sur Telegram et ntfy, et le workflow hebdomadaire."
  }

  # Échéances de rotation des secrets, chaque lundi
  # (.github/workflows/secrets-rotation.yaml) : un run par semaine, plus un
  # jour de marge, sous le plafond de 24 jours du provider.
  assert {
    condition = (
      uptimekuma_monitor_push.secrets_rotation.parent == uptimekuma_monitor_group.self_hosted.id
      && uptimekuma_monitor_push.secrets_rotation.interval > 7 * 86400
      && uptimekuma_monitor_push.secrets_rotation.interval < 24 * 86400
      && uptimekuma_monitor_push.secrets_rotation.active == true
      && toset(uptimekuma_monitor_push.secrets_rotation.notification_ids) == toset(local.alert_notification_ids)
      && strcontains(file("${path.module}/../../.github/workflows/secrets-rotation.yaml"), "- cron: \"30 6 * * 1\"")
    )
    error_message = "Le moniteur Rotation des secrets doit être dans le dossier Self-hosted, entre une semaine et 24 jours, actif et notifié sur Telegram et ntfy, et le workflow hebdomadaire."
  }

  # Le workflow teste les dépôts de .github/restore-test/apps.json : un par
  # moniteur de sauvegarde, Pangolin et Jellyfin compris. Une app ajoutée avec
  # `backup = true` doit y entrer, une app retirée en sortir.
  assert {
    condition     = sort(keys(jsondecode(file("${path.module}/../../.github/restore-test/apps.json")))) == sort(concat(keys(uptimekuma_monitor_push.backup), ["pangolin", "jellyfin"]))
    error_message = ".github/restore-test/apps.json doit lister exactement les apps qui ont un moniteur Backup, Pangolin et Jellyfin compris."
  }

  # Une app en pause n'écrit plus d'archive : le test planifié la saute
  # ("paused": true), exactement quand son moniteur de sauvegarde est en pause.
  assert {
    condition = sort([
      for key, app in jsondecode(file("${path.module}/../../.github/restore-test/apps.json")) : key if lookup(app, "paused", false)
      ]) == sort([
      for key, m in uptimekuma_monitor_push.backup : key if !m.active
    ])
    error_message = "\"paused\": true dans .github/restore-test/apps.json doit marquer exactement les apps dont le moniteur Backup est en pause."
  }

  # Chaque dépôt est sous backup/<hôte>/ : l'hôte doit avoir un sous-compte
  # (backup_storage_box_hosts, ansible/host_vars/backups).
  assert {
    condition = alltrue([
      for app in values(jsondecode(file("${path.module}/../../.github/restore-test/apps.json"))) :
      contains(yamldecode(file("${path.module}/../../ansible/host_vars/backups/variables.yaml")).backup_storage_box_hosts, app.host)
    ])
    error_message = "Chaque entrée de .github/restore-test/apps.json doit nommer un hôte de backup_storage_box_hosts."
  }


  assert {
    condition = (
      uptimekuma_monitor_push.cron_geoip.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_geoip.notification_ids) == toset(local.alert_notification_ids)
      && uptimekuma_monitor_push.cron_geoip.interval < 60 * 60 * 24 * 24
      && uptimekuma_monitor_push.cron_geoip.interval > 60 * 60 * 24 * 7
      && uptimekuma_monitor_push.cron_nas_cert.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_nas_cert.notification_ids) == toset(local.alert_notification_ids)
      && uptimekuma_monitor_push.cron_monica.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_monica.notification_ids) == toset(local.alert_notification_ids)
    )
    error_message = "Le cron de Monica n'est pas une sauvegarde : il est rangé avec les healthchecks et notifié sur Telegram et ntfy."
  }

  # Le reset du bêtisier tourne une fois par jour (betisier-reset.timer) : une
  # nuit manquée passe, pas deux.
  assert {
    condition = (
      uptimekuma_monitor_push.cron_betisier_reset.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_betisier_reset.notification_ids) == toset(local.alert_notification_ids)
      && strcontains(file("${path.module}/../../ansible/roles/betisier/templates/betisier-reset.timer.j2"), "OnCalendar=daily")
      && uptimekuma_monitor_push.cron_betisier_reset.interval > 60 * 60 * 24 * 2
      && uptimekuma_monitor_push.cron_betisier_reset.interval < 60 * 60 * 24 * 3
    )
    error_message = "Reset Betisier : rangé avec les healthchecks, notifié sur Telegram et ntfy, timer quotidien et intervalle de deux à trois jours."
  }

  # Le reset de la vitrine aussi (exemple_planning-reset.timer, rôle
  # flip_planning) : même règle.
  assert {
    condition = (
      uptimekuma_monitor_push.cron_exemple_planning_reset.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_exemple_planning_reset.notification_ids) == toset(local.alert_notification_ids)
      && length(regexall("flip_planning_reset_on_calendar: \"\\*-\\*-\\* [0-9:]+ Europe/Paris\"", file("${path.module}/../../ansible/roles/flip_planning/defaults/main.yml"))) == 1
      && uptimekuma_monitor_push.cron_exemple_planning_reset.interval > 60 * 60 * 24 * 2
      && uptimekuma_monitor_push.cron_exemple_planning_reset.interval < 60 * 60 * 24 * 3
    )
    error_message = "Reset Exemple Planning : rangé avec les healthchecks, notifié sur Telegram et ntfy, timer quotidien et intervalle de deux à trois jours."
  }

  # Le NAS pousse une fois par jour (nas-proxy-cert-check.timer, rôle
  # nas_proxy) : l'intervalle laisse passer une journée manquée, pas deux. Le
  # seuil reste sous les 30 jours avant l'échéance où Traefik renouvelle, sinon
  # chaque certificat frais serait « down ».
  assert {
    condition = (
      can(regex("^\\*-\\*-\\* [0-9]{2}:[0-9]{2}:[0-9]{2}$", yamldecode(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml")).nas_proxy_cert_check_schedule))
      && uptimekuma_monitor_push.cron_nas_cert.interval > 60 * 60 * 24 * 2
      && uptimekuma_monitor_push.cron_nas_cert.interval < 60 * 60 * 24 * 3
      && yamldecode(file("${path.module}/../../ansible/roles/nas_proxy/defaults/main.yml")).nas_proxy_cert_check_min_days < 30
    )
    error_message = "Certificats NAS : timer quotidien, intervalle de deux à trois jours, seuil sous les 30 jours du renouvellement de Traefik."
  }

  # La copie de kDrive (kdrive-sync.timer, rôle kdrive_sync) : une fois par
  # nuit, entre 03:00 et 07:00, hors des sauvegardes borg (01:00 sur les autres
  # hôtes, 02:30 sur le NAS lui-même) et avant le test de restauration ;
  # l'intervalle laisse passer une nuit manquée, pas deux, et la copie est
  # bornée sous la journée pour que le timer du lendemain reparte.
  assert {
    condition = (
      can(regex("^\\*-\\*-\\* 0[3-6]:[0-9]{2}:[0-9]{2}$", yamldecode(file("${path.module}/../../ansible/roles/kdrive_sync/defaults/main.yml")).kdrive_sync_schedule))
      && can(regex("^([1-9]|1[0-9]|2[0-3])h$", yamldecode(file("${path.module}/../../ansible/roles/kdrive_sync/defaults/main.yml")).kdrive_sync_timeout))
      && uptimekuma_monitor_push.cron_kdrive_sync.interval > 60 * 60 * 24 * 2
      && uptimekuma_monitor_push.cron_kdrive_sync.interval < 60 * 60 * 24 * 3
      && uptimekuma_monitor_push.cron_kdrive_sync.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_kdrive_sync.notification_ids) == toset(local.alert_notification_ids)
    )
    error_message = "kDrive vers NAS : timer quotidien entre 03:00 et 07:00, copie bornée sous 24 h, intervalle de deux à trois jours, rangé avec les healthchecks et notifié sur Telegram et ntfy."
  }

  # Le vérificateur de mises à jour (rôle update_notify) passe une fois par
  # semaine sur chaque hôte Debian : l'intervalle laisse passer une semaine
  # manquée, pas deux, sous le plafond de 24 jours d'Uptime Kuma. Chaque
  # playbook joue le rôle et lui donne le moniteur de SON hôte.
  assert {
    condition = (
      can(regex("^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \\*-\\*-\\* [0-9]{2}:[0-9]{2}:[0-9]{2}$", yamldecode(file("${path.module}/../../ansible/roles/update_notify/defaults/main.yml")).update_notify_schedule))
      && toset(keys(local.update_check_hosts)) == toset(["docker", "flip", "pangolin", "pi", "pve"])
      && alltrue([
        for host, playbook in {
          pve      = "pve.yml"
          docker   = "docker.yml"
          pi       = "pi.yml"
          flip     = "flip.yml"
          pangolin = "pangolin.yaml"
        } :
        uptimekuma_monitor_push.cron_updates[host].interval > 60 * 60 * 24 * 14
        && uptimekuma_monitor_push.cron_updates[host].interval < 60 * 60 * 24 * 24
        && uptimekuma_monitor_push.cron_updates[host].parent == uptimekuma_monitor_group.self_hosted.id
        && toset(uptimekuma_monitor_push.cron_updates[host].notification_ids) == toset(local.alert_notification_ids)
        && strcontains(file("${path.module}/../../ansible/${playbook}"), "update_notify_healthcheck_url: \"{{ terraform_outputs.uptime_cron_${host}_updates_url.value | default('') }}\"")
        && strcontains(file("${path.module}/../../ansible/${playbook}"), "- role: update_notify\n")
      ])
    )
    error_message = "Mises à jour (update_notify) : timer hebdomadaire ; un moniteur par hôte (pve, docker, pi, flip, pangolin), rangé avec les healthchecks, Telegram et ntfy, intervalle de deux semaines à 24 jours ; le playbook de l'hôte joue le rôle et lui donne son URL push."
  }

  # Blocky (rôle blocky) : chaque hôte pousse toutes les 5 minutes
  # (blocky-check.timer) ; l'intervalle laisse passer deux vérifications
  # manquées, pas trois. Telegram et ntfy, comme les autres.
  assert {
    condition = alltrue([
      for m in values(uptimekuma_monitor_push.cron_dns) :
      m.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(m.notification_ids) == toset(local.alert_notification_ids)
      && m.interval == 3 * 60 * tonumber(regex("^\\*:0/([0-9]+)$", yamldecode(file("${path.module}/../../ansible/roles/blocky/defaults/main.yml")).blocky_check_schedule)[0])
    ])
    error_message = "Moniteurs DNS : rangés avec les healthchecks, Telegram et ntfy, intervalle de trois périodes de blocky_check_schedule (*:0/N)."
  }

  # Abonnés ntfy (rôle ntfy) : la VM docker pousse toutes les N minutes
  # (ntfy-subscribers-check.timer) ; l'intervalle laisse passer deux
  # vérifications manquées, pas trois, et la fenêtre relue couvre au moins
  # deux relevés « Server stats » (un par minute) ; elle peut dépasser
  # l'intervalle (8 h : un téléphone hors ligne une nuit n'alerte pas).
  # Telegram compris : ntfy, lui, ne joindrait plus les téléphones.
  assert {
    condition = (
      uptimekuma_monitor_push.cron_ntfy_subscribers.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(uptimekuma_monitor_push.cron_ntfy_subscribers.notification_ids) == toset(local.alert_notification_ids)
      && uptimekuma_monitor_push.cron_ntfy_subscribers.active == true
      && uptimekuma_monitor_push.cron_ntfy_subscribers.interval == 3 * 60 * tonumber(regex("^\\*:0/([0-9]+)$", yamldecode(file("${path.module}/../../ansible/roles/ntfy/defaults/main.yml")).ntfy_subscribers_check_schedule)[0])
      && yamldecode(file("${path.module}/../../ansible/roles/ntfy/defaults/main.yml")).ntfy_subscribers_check_window_minutes >= 2
    )
    error_message = "Abonnés ntfy : rangé avec les healthchecks, Telegram et ntfy, actif, intervalle de trois périodes de ntfy_subscribers_check_schedule (*:0/N), fenêtre d'au moins 2 minutes."
  }

  assert {
    condition = alltrue([
      for m in concat(values(uptimekuma_monitor_http_keyword.healthcheck), [uptimekuma_monitor_http.pangolin_dashboard]) :
      m.parent == uptimekuma_monitor_group.self_hosted.id
      && toset(m.notification_ids) == toset(local.alert_notification_ids)
    ])
    error_message = "Chaque healthcheck doit être dans le dossier Self-hosted et notifié sur Telegram et ntfy."
  }

  # Chaque healthcheck sonde le FQDN de SA ressource, suivi de son
  # monitor_path quand la racine ne répond pas 200 (POST seul, 404, 401,
  # redirection : voir le champ dans website_<app>.tf).
  assert {
    condition = alltrue([
      for key, m in uptimekuma_monitor_http_keyword.healthcheck :
      m.url == "https://${pangolin_resource.website[key].full_domain}${lookup(local.websites[key], "monitor_path", "")}"
    ])
    error_message = "Un healthcheck ne sonde pas https://<FQDN de sa ressource><monitor_path>."
  }

  # Telegram et ntfy, l'un ne passant pas par Pangolin, l'autre si : plus
  # de canal e-mail (supprimé le 2026-10-29).
  assert {
    condition = (
      toset(local.alert_notification_ids) == toset([uptimekuma_notification_telegram.supervision.id, uptimekuma_notification_ntfy.ntfy.id])
      && length(distinct(local.alert_notification_ids)) == 2
    )
    error_message = "Les moniteurs alertent sur Telegram et ntfy (local.alert_notification_ids), et sur eux seuls."
  }

  # Les moniteurs externes (external_monitors.tf) alertent comme les autres.
  assert {
    condition = alltrue([
      for m in [
        uptimekuma_monitor_http.actualbudget,
        uptimekuma_monitor_http.redirect,
        uptimekuma_monitor_http.blog,
        uptimekuma_monitor_http.blog_apex,
        uptimekuma_monitor_http.ref,
        uptimekuma_monitor_http.agent_ready_cloudflare,
        uptimekuma_monitor_http.kdrive,
        uptimekuma_monitor_http.simplelogin,
        uptimekuma_monitor_http.ustalence_tt,
        uptimekuma_monitor_push.foldersync,
      ] : toset(m.notification_ids) == toset(local.alert_notification_ids)
    ])
    error_message = "Chaque moniteur externe (et FolderSync) alerte sur Telegram et ntfy."
  }
}

# Alerte de connexion SSH (issue #451, ssh_login_monitors.tf) : un moniteur
# push inversé par hôte, notifié sur Telegram, et une URL par hôte lue par
# 00-setup.yaml sous la clé inventory_hostname. Un hôte renommé d'un côté et
# pas de l'autre donnerait une URL vide : le rôle ne poserait rien, en silence
# hormis un avertissement.
run "ssh_login_monitors_alert_on_every_login" {
  command = apply

  # Inversé : un push le fait passer DOWN (la notification), 60 s sans push le
  # ramènent UP. Non inversé, chaque hôte serait DOWN en permanence faute de
  # battement. max_retries = 0 : pas de PENDING, la première connexion alerte.
  assert {
    condition = alltrue([
      for m in values(uptimekuma_monitor_push.ssh_login) :
      m.upside_down == true
      && m.interval == 60
      && m.retry_interval == 60
      && m.max_retries == 0
      && m.resend_interval == 0
      && m.active == true
      && m.parent == uptimekuma_monitor_group.ssh_logins.id
    ])
    error_message = "Chaque moniteur SSH doit être inversé, sur 60 s, sans retry ni renvoi, actif, dans le dossier Connexions SSH."
  }

  # Telegram seul (notifications.tf) : une alerte de connexion doit arriver
  # tout de suite, sans passer par ntfy.
  assert {
    condition = alltrue([
      for m in values(uptimekuma_monitor_push.ssh_login) :
      toset(m.notification_ids) == toset([uptimekuma_notification_telegram.supervision.id])
    ])
    error_message = "Les moniteurs SSH notifient la notification Telegram, et elle seule."
  }

  # Ni canal par défaut ni rattachement en masse ; le chat vient de la clé
  # SOPS.
  assert {
    condition = (
      uptimekuma_notification_telegram.supervision.is_default == false
      && uptimekuma_notification_telegram.supervision.apply_existing == false
      && uptimekuma_notification_telegram.supervision.is_active == true
      && uptimekuma_notification_telegram.supervision.chat_id == "-100123456789"
    )
    error_message = "La notification Telegram n'est ni par défaut ni rattachée en masse, et lit son chat dans uptimekuma_telegram_chat_id."
  }

  assert {
    condition = output.uptime_ssh_login_urls == {
      docker     = "https://uptime.example.test/api/push/push-ssh-docker"
      flip       = "https://uptime.example.test/api/push/push-ssh-flip"
      "newt-lxc" = "https://uptime.example.test/api/push/push-ssh-newt-lxc"
      pangolin   = "https://uptime.example.test/api/push/push-ssh-pangolin"
      pi         = "https://uptime.example.test/api/push/push-ssh-pi"
    }
    error_message = "uptime_ssh_login_urls doit donner à chaque hôte l'URL de SON moniteur push."
  }

  # Contrat Tofu <-> Ansible : 00-setup.yaml lit la sortie sous la clé
  # inventory_hostname et applique le rôle ssh_login_notify.
  assert {
    condition = (
      strcontains(file("${path.module}/../../ansible/00-setup.yaml"), "terraform_outputs.uptime_ssh_login_urls.value[inventory_hostname]")
      && strcontains(file("${path.module}/../../ansible/00-setup.yaml"), "role: ssh_login_notify")
    )
    error_message = "00-setup.yaml doit lire terraform_outputs.uptime_ssh_login_urls.value[inventory_hostname] et appliquer le rôle ssh_login_notify."
  }

  # Seul le setup de base tolère un state illisible (terraform_outputs = {}) :
  # ailleurs une URL vide passerait en silence (sauvegardes sans moniteur,
  # Newt sans identifiants).
  assert {
    condition = (
      strcontains(file("${path.module}/../../ansible/00-setup.yaml"), "pangolin_config_outputs_optional: true")
      && alltrue([
        for playbook in ["docker.yml", "flip.yml", "lxc.yml", "nas.yml", "pangolin.yaml", "pi.yml", "pve.yml"] :
        !strcontains(file("${path.module}/../../ansible/${playbook}"), "pangolin_config_outputs_optional")
      ])
    )
    error_message = "pangolin_config_outputs_optional: true dans 00-setup.yaml, et dans aucun autre playbook."
  }

  # Les clés sont des inventory_hostname : chacune a son dossier host_vars.
  assert {
    condition = alltrue([
      for host in local.ssh_login_hosts :
      length(fileset("${path.module}/../../ansible/host_vars/${host}", "*")) > 0
    ])
    error_message = "Chaque hôte de local.ssh_login_hosts doit être un hôte de l'inventaire (ansible/host_vars/<hôte>)."
  }
}

# Homepage montre un lien par application publique : l'output homepage_links
# est tiré de local.websites (website_homepage.tf), lu par docker.yml, et ses
# groupes doivent être ceux que le rôle homepage sait ranger.
run "homepage_links_cover_every_public_app" {
  command = plan

  # Toutes les entrées, sauf Homepage elle-même et Promptoramix (racine en
  # POST seulement) : une application publiée sans lien fait échouer le plan
  # (champ homepage lu sur chaque entrée), une entrée masquée l'est ici.
  assert {
    condition     = toset(keys(output.homepage_links)) == setsubtract(toset([for key, website in local.websites : key if lookup(website, "enabled", true)]), ["homepage", "promptoramix"])
    error_message = "homepage_links doit couvrir chaque entrée de local.websites, sauf Homepage et Promptoramix (homepage = null)."
  }

  assert {
    condition = alltrue([
      for key, link in output.homepage_links :
      startswith(link.href, "https://") && length(link.name) > 0 && length(link.group) > 0 && length(link.description) > 0
    ])
    error_message = "Chaque lien de Homepage porte un nom, un groupe, une description et une URL https."
  }

  assert {
    condition = (
      output.homepage_links["trek"].href == "https://travels.sylvain.cloud"
      && output.homepage_links["trek"].name == "TREK"
      && output.homepage_links["rss"].name == "FreshRSS"
    )
    error_message = "Le lien de Homepage vise le full_domain de la ressource, sous le nom de la ressource ou le titre de son champ homepage."
  }

  # Adresse interne (widgets, pastille siteMonitor du rôle homepage) : la
  # cible de Pangolin et sa sonde, pour les seules cibles de la VM docker,
  # que Homepage joint par leur nom sur newt. Vide pour le Pi et flip.
  assert {
    condition = (
      output.homepage_links["trek"].internal_url == "http://trek:3000"
      && output.homepage_links["trek"].site_monitor == "http://trek:3000/api/health"
      && output.homepage_links["betisier"].site_monitor == "http://betisier:80/"
      && output.homepage_links["immich"].internal_url == ""
      && output.homepage_links["immich"].site_monitor == ""
      && output.homepage_links["flip_planning"].site_monitor == ""
    )
    error_message = "internal_url/site_monitor de homepage_links : la cible de Pangolin (et sa sonde) sur la VM docker seulement, vides ailleurs."
  }

  assert {
    condition = alltrue([
      for key, link in output.homepage_links :
      (link.internal_url == "") == (link.site_monitor == "")
    ])
    error_message = "Un lien de Homepage porte internal_url et site_monitor ensemble, ou aucun des deux."
  }

  assert {
    condition     = output.homepage_pangolin_org == "homelab"
    error_message = "homepage_pangolin_org doit être l'organisation du fournisseur (pangolin_org_id)."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/docker.yml"), "homepage_pangolin_org: \"{{ terraform_outputs.homepage_pangolin_org.value | default('') }}\"")
    error_message = "docker.yml doit lire homepage_pangolin_org de l'output du même nom."
  }

  # Un groupe inconnu du rôle s'afficherait quand même, après les autres : la
  # liste du rôle fixe l'ordre, une faute de frappe la contournerait.
  assert {
    condition = length(setsubtract(
      toset([for link in values(output.homepage_links) : link.group]),
      toset(yamldecode(file("${path.module}/../../ansible/roles/homepage/defaults/main.yml")).homepage_groups),
    )) == 0
    error_message = "Un groupe de homepage_links manque à homepage_groups (ansible/roles/homepage/defaults/main.yml)."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/docker.yml"), "terraform_outputs.homepage_links.value | default({})")
    error_message = "docker.yml doit passer l'output homepage_links au rôle homepage (homepage_websites)."
  }
}

# ntfy : les topics ouverts à la publication sans SSO (local.ntfy_publish_topics)
# sont exactement ceux des producteurs du rôle (ntfy_publishers), et la
# notification Uptime Kuma publie sur le sien, avec son jeton, sans être
# encore branchée sur aucun moniteur (décision de Sylvain), jeton que
# docker.yml relit dans ce state.
run "ntfy_topics_match_the_role" {
  command = plan

  assert {
    condition = sort(local.ntfy_publish_topics) == sort([
      for publisher in yamldecode(file("${path.module}/../../ansible/roles/ntfy/defaults/main.yml")).ntfy_publishers :
      publisher.topic
    ])
    error_message = "local.ntfy_publish_topics (website_ntfy.tf) doit lister les topics de ntfy_publishers (ansible/roles/ntfy/defaults/main.yml)."
  }

  assert {
    condition = (
      uptimekuma_notification_ntfy.ntfy.server_url == "https://ntfy.sylvain.cloud"
      && uptimekuma_notification_ntfy.ntfy.topic == "uptime-kuma"
      && uptimekuma_notification_ntfy.ntfy.authentication_method == "accessToken"
      && uptimekuma_notification_ntfy.ntfy.is_default == false
      && uptimekuma_notification_ntfy.ntfy.apply_existing == false
      && contains(local.ntfy_publish_topics, uptimekuma_notification_ntfy.ntfy.topic)
    )
    error_message = "La notification ntfy d'Uptime Kuma doit publier sur ntfy.sylvain.cloud/uptime-kuma avec un jeton, sans s'imposer aux moniteurs."
  }

  assert {
    condition = (
      nonsensitive(output.ntfy_uptime_kuma_token == uptimekuma_notification_ntfy.ntfy.access_token)
      && strcontains(file("${path.module}/../../ansible/docker.yml"), "terraform_outputs.ntfy_uptime_kuma_token.value | default('')")
    )
    error_message = "docker.yml doit lire le jeton uptime-kuma de ntfy dans la sortie ntfy_uptime_kuma_token, celui de la notification."
  }

  # « / » est ouvert sans SSO et répond 404 à un GET (web-root: /app) : le
  # lien Homepage mène à /app, le moniteur sonde la route de santé.
  assert {
    condition = (
      output.homepage_links["ntfy"].href == "https://${pangolin_resource.website["ntfy"].full_domain}/app"
      && local.websites["ntfy"].monitor_path == "/v1/health"
      && strcontains(file("${path.module}/../../ansible/roles/ntfy/templates/server.yml.j2"), "\nweb-root: /app\n")
    )
    error_message = "ntfy : le lien Homepage doit viser /app, le moniteur /v1/health, et server.yml garder web-root: /app."
  }
}

# Le widget Uptime Kuma de Homepage lit une page de statut publiée par son slug
# (homepage_uptimekuma_status_pages du rôle homepage) : chaque slug du rôle
# doit être celui d'une page déclarée ici, sinon le widget affiche une erreur.
# Aucune page de statut des sauvegardes (décision de Sylvain : rien de public
# sur elles). docker.yml lit l'URL d'Uptime Kuma de son output.
run "homepage_status_pages_match_the_role" {
  command = plan

  assert {
    condition = toset([
      for page in yamldecode(file("${path.module}/../../ansible/roles/homepage/defaults/main.yml")).homepage_uptimekuma_status_pages : page.slug
    ]) == toset([uptimekuma_status_page.site.slug])
    error_message = "homepage_uptimekuma_status_pages (rôle homepage) doit lister exactement le slug de la page de statut sylvain-dev."
  }

  assert {
    condition     = uptimekuma_status_page.site.published
    error_message = "Le widget de Homepage lit la page sans compte : elle doit rester publiée."
  }

  # homepage_link_widgets (rôle homepage) pose le widget Beszel sur le lien de
  # clé beszel : renommer l'entrée le ferait disparaître sans un mot.
  assert {
    condition = (
      strcontains(file("${path.module}/../../ansible/roles/homepage/defaults/main.yml"), "{{ {'beszel': {'type': 'beszel'")
      && contains(keys(output.homepage_links), "beszel")
    )
    error_message = "Le widget Beszel de Homepage est posé sur le lien de clé beszel de homepage_links : l'entrée beszel de local.websites ne doit pas être renommée sans homepage_link_widgets."
  }

  assert {
    condition     = output.homepage_uptimekuma_url == "https://uptime.example.test"
    error_message = "homepage_uptimekuma_url doit être l'URL d'Uptime Kuma (UPTIMEKUMA_ENDPOINT), sans chemin."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/docker.yml"), "homepage_uptimekuma_url: \"{{ terraform_outputs.homepage_uptimekuma_url.value | default('') }}\"")
    error_message = "docker.yml doit lire homepage_uptimekuma_url de l'output du même nom."
  }
}
