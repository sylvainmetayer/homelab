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

# --- Réponses réalistes de l'API Pangolin (cas nominal) ---------------------

# GET /v1/org/{org}/resources?pageSize=1000 : les 21 ressources gérées, dont
# Gramps désactivée, et un reste désactivé créé dans l'UI, que l'audit doit
# ignorer puisqu'il n'est pas servi.
override_data {
  target = data.http.pangolin_resources
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"resources": [
        {"resourceId": 21, "niceId": "betisier", "name": "Betisier", "fullDomain": "betisier.sylvain.dev", "sso": false, "enabled": true},
        {"resourceId": 60, "niceId": "dawarich", "name": "Dawarich", "fullDomain": "tracks.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 81, "niceId": "demo-planning", "name": "Demo Planning", "fullDomain": "demo-planning.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 82, "niceId": "demo-planning-kc", "name": "Demo Planning KC", "fullDomain": "demo-planning-kc.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 22, "niceId": "echo", "name": "Echo", "fullDomain": "echo.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 80, "niceId": "flip-planning", "name": "Flip Planning", "fullDomain": "flip-planning.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 55, "niceId": "gramps", "name": "Gramps", "fullDomain": "trees.sylvain.cloud", "sso": true, "enabled": false},
        {"resourceId": 10, "niceId": "immich", "name": "Immich", "fullDomain": "photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 23, "niceId": "immich-swipe", "name": "Immich Swipe", "fullDomain": "swipe-photos.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 62, "niceId": "karakeep", "name": "Karakeep", "fullDomain": "keep.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 30, "niceId": "meerkat-crm", "name": "Meerkat CRM", "fullDomain": "crm.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 31, "niceId": "monica", "name": "Monica CRM", "fullDomain": "crm.sylvain.dev", "sso": true, "enabled": true},
        {"resourceId": 75, "niceId": "nas", "name": "NAS", "fullDomain": "nas.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 11, "niceId": "nextcloud", "name": "nextcloud", "fullDomain": "sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 40, "niceId": "paperless", "name": "Paperless-ngx", "fullDomain": "papiers.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 4, "niceId": "proxmox", "name": "Proxmox", "fullDomain": "proxmox.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 32, "niceId": "rss", "name": "RSS", "fullDomain": "rss.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 56, "niceId": "scanopy", "name": "Scanopy", "fullDomain": "scan.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 41, "niceId": "searxng", "name": "SearXNG", "fullDomain": "search.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 61, "niceId": "trek", "name": "TREK", "fullDomain": "travels.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 33, "niceId": "wiki", "name": "Wiki (Bookstack)", "fullDomain": "wiki.sylvain.cloud", "sso": true, "enabled": true},
        {"resourceId": 90, "niceId": "test-manuel", "name": "Test manuel", "fullDomain": "test.sylvain.cloud", "sso": true, "enabled": false}
      ], "pagination": {"total": 22, "pageSize": 1000, "page": 1}},
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
# règles spécifiques (2004 à 2011) : si l'une d'elles disparaît de
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
        {"ruleId": 2011, "action": "ACCEPT", "match": "PATH", "value": "/share/*", "priority": 4, "enabled": true},
        {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
      ], "pagination": {"total": 8, "pageSize": 1000, "page": 1}},
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

# Ressources publiques : un identifiant par instance de pangolin_resource.website
# (une surcharge peut viser une seule instance d'un for_each, vérifié sur
# OpenTofu 1.13), ceux de l'API quand un commentaire du code les cite
# (Proxmox 4, NAS 75).
override_resource {
  target = pangolin_resource.website["betisier"]
  values = { id = 21 }
}

override_resource {
  target = pangolin_resource.website["dawarich"]
  values = { id = 60 }
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
  target = pangolin_resource.website["echo"]
  values = { id = 22 }
}

override_resource {
  target = pangolin_resource.website["flip_planning"]
  values = { id = 80, full_domain = "flip-planning.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["gramps"]
  values = { id = 55 }
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
  target = pangolin_resource.website["karakeep"]
  values = { id = 62 }
}

override_resource {
  target = pangolin_resource.website["meerkat_crm"]
  values = { id = 30 }
}

override_resource {
  target = pangolin_resource.website["monica"]
  values = { id = 31 }
}

override_resource {
  target = pangolin_resource.website["nas"]
  values = { id = 75 }
}

override_resource {
  target = pangolin_resource.website["nextcloud"]
  values = { id = 11 }
}

override_resource {
  target = pangolin_resource.website["paperless"]
  values = { id = 40 }
}

override_resource {
  target = pangolin_resource.website["proxmox"]
  values = { id = 4 }
}

override_resource {
  target = pangolin_resource.website["rss"]
  values = { id = 32 }
}

override_resource {
  target = pangolin_resource.website["scanopy"]
  values = { id = 56 }
}

override_resource {
  target = pangolin_resource.website["searxng"]
  values = { id = 41 }
}

override_resource {
  target = pangolin_resource.website["trek"]
  values = { id = 61, full_domain = "travels.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.website["wiki"]
  values = { id = 33 }
}

# Jetons d'accès : ceux des clients MCP de TREK, et ceux des healthchecks de
# Flip Planning, un par environnement.
override_resource {
  target = pangolin_resource_access_token.trek_mcp_clients
  values = { id = "tok-trek-mcp", token = "jeton-trek-mcp" }
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
  target = uptimekuma_notification_smtp.email
  values = { id = 7 }
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
  target = uptimekuma_monitor_push.backup["gramps"]
  values = { push_token = "push-gramps" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["immich"]
  values = { push_token = "push-immich" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["meerkat_crm"]
  values = { push_token = "push-meerkat-crm" }
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
  target = uptimekuma_monitor_push.backup["paperless"]
  values = { push_token = "push-paperless" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["rss"]
  values = { push_token = "push-rss" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["scanopy"]
  values = { push_token = "push-scanopy" }
}

override_resource {
  target = uptimekuma_monitor_push.backup["searxng"]
  values = { push_token = "push-searxng" }
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
  target = uptimekuma_monitor_push.backup["wiki"]
  values = { push_token = "push-wiki" }
}

# ===========================================================================
# Runs `plan` : valeurs issues de la configuration
# ===========================================================================

# Chaque cible sondée déclare hc_scheme / hc_mode / hc_port. Ils sont
# optionnels+calculés : non déclarés, Pangolin a stocké NULL pour gramps et
# scanopy, la sonde ne pouvait jamais réussir et les deux sites ont servi
# "no available server" pendant que `tofu plan` ne voyait rien.
#
# Les cibles des applications sont les instances de pangolin_target.website
# (websites.tf), plus celle de Proxmox, recopiée de l'API ; seule celle du NAS
# n'a pas de sonde. Les clés sont les anciens noms des ressources, ceux que
# moved.tf vise : une clé qui change recréerait la cible.
run "every_probed_target_declares_scheme_mode_and_port" {
  command = plan

  assert {
    condition = alltrue([
      for t in concat(values(pangolin_target.website), [pangolin_target.proxmox]) :
      t.hc_enabled == true
      && contains(["http", "https"], t.hc_scheme)
      && t.hc_mode == "http"
      && t.hc_port != null
    ])
    error_message = "Une cible sondée n'a pas hc_scheme (http/https), hc_mode = \"http\" ou hc_port : Pangolin stockerait NULL et la sonde échouerait toujours."
  }

  assert {
    condition = toset(keys(pangolin_target.website)) == toset([
      "betisier", "dawarich", "echo", "gramps", "immich", "immich_swipe", "karakeep",
      "meerkat_crm", "monica", "nextcloud", "paperless", "rss", "scanopy", "searxng", "trek", "wiki",
      "flip_planning", "flip_planning_pgadmin", "flip_planning_mailpit", "flip_planning_assets",
      "demo_planning", "demo_planning_pgadmin", "demo_planning_mailpit", "demo_planning_assets",
      "demo_planning_kc", "demo_planning_kc_pgadmin", "demo_planning_kc_mailpit", "demo_planning_kc_assets",
      "demo_planning_kc_keycloak",
    ])
    error_message = "Les cibles des applications ont changé : chaque clé de pangolin_target.website doit garder le nom de l'ancienne ressource (moved.tf), et une nouvelle cible être listée ici."
  }

  assert {
    condition     = pangolin_target.nas.hc_enabled == false
    error_message = "La cible du NAS est la seule sans sonde, recopiée de l'API (website_nas.tf)."
  }
}

# hc_hostname explicite et égal à `ip` : la sonde envoie le bon Host au bon
# conteneur. Le provider ne le déduit pas de `ip`.
run "probed_targets_set_hc_hostname_to_their_ip" {
  command = plan

  assert {
    condition = alltrue([
      for t in concat(values(pangolin_target.website), [pangolin_target.proxmox]) :
      t.hc_hostname == t.ip
    ])
    error_message = "Une cible a un hc_hostname absent ou différent de son ip."
  }
}

# Routage par chemin : la cible attrape-tout "/" doit avoir le numéro de
# priorité le PLUS BAS de sa ressource, sinon elle avale /db, /mail, /assets
# et /auth. Les priorités d'une même ressource sont toutes distinctes.
run "catch_all_target_has_lowest_priority" {
  command = plan

  assert {
    condition = (
      pangolin_target.website["flip_planning"].path == "/"
      && alltrue([
        for t in [
          pangolin_target.website["flip_planning_pgadmin"],
          pangolin_target.website["flip_planning_mailpit"],
          pangolin_target.website["flip_planning_assets"],
        ] : t.path != "/" && t.priority > pangolin_target.website["flip_planning"].priority
      ])
    )
    error_message = "Flip Planning : la cible \"/\" doit avoir une priorité plus basse que /db, /mail et /assets."
  }

  assert {
    condition = (
      pangolin_target.website["demo_planning"].path == "/"
      && alltrue([
        for t in [
          pangolin_target.website["demo_planning_pgadmin"],
          pangolin_target.website["demo_planning_mailpit"],
          pangolin_target.website["demo_planning_assets"],
        ] : t.path != "/" && t.priority > pangolin_target.website["demo_planning"].priority
      ])
    )
    error_message = "Demo Planning : la cible \"/\" doit avoir une priorité plus basse que /db, /mail et /assets."
  }

  assert {
    condition = (
      pangolin_target.website["demo_planning_kc"].path == "/"
      && alltrue([
        for t in [
          pangolin_target.website["demo_planning_kc_pgadmin"],
          pangolin_target.website["demo_planning_kc_mailpit"],
          pangolin_target.website["demo_planning_kc_assets"],
          pangolin_target.website["demo_planning_kc_keycloak"],
        ] : t.path != "/" && t.priority > pangolin_target.website["demo_planning_kc"].priority
      ])
    )
    error_message = "Demo Planning KC : la cible \"/\" doit avoir une priorité plus basse que /db, /mail, /assets et /auth."
  }

  assert {
    condition = alltrue([
      for group in [
        [
          pangolin_target.website["flip_planning"],
          pangolin_target.website["flip_planning_pgadmin"],
          pangolin_target.website["flip_planning_mailpit"],
          pangolin_target.website["flip_planning_assets"],
        ],
        [
          pangolin_target.website["demo_planning"],
          pangolin_target.website["demo_planning_pgadmin"],
          pangolin_target.website["demo_planning_mailpit"],
          pangolin_target.website["demo_planning_assets"],
        ],
        [
          pangolin_target.website["demo_planning_kc"],
          pangolin_target.website["demo_planning_kc_pgadmin"],
          pangolin_target.website["demo_planning_kc_mailpit"],
          pangolin_target.website["demo_planning_kc_assets"],
          pangolin_target.website["demo_planning_kc_keycloak"],
        ],
      ] :
      length(distinct([for t in group : t.priority])) == length(group)
      && length(distinct([for t in group : t.path])) == length(group)
      && alltrue([for t in group : t.path_match_type == "prefix"])
    ])
    error_message = "Les cibles d'une même ressource multi-chemins doivent avoir des priorités et des chemins distincts, en correspondance par préfixe."
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

# La bande de priorités de rules.tf : les règles qui doivent décider quelle que
# soit l'origine sont AVANT les PASS pays (1-9), les ACCEPT d'IP maison en
# dernier de cette bande (9), et le DROP ALL en dernier (99).
run "bypass_rules_sit_in_their_priority_band" {
  command = plan

  # Les ACCEPT par chemin des trois instances de Flip Planning, passés de
  # ressources autonomes à local.path_bypasses : rien de plus large que /mcp/*
  # (planning) et /auth/* (Keycloak du banc KC). Le reste de leurs règles est
  # vérifié par path_bypasses_open_exactly_the_reviewed_paths.
  assert {
    condition = (
      pangolin_resource_rule.path_bypass["Flip Planning /mcp/*"].priority == 2
      && pangolin_resource_rule.path_bypass["Demo Planning /mcp/*"].priority == 2
      && pangolin_resource_rule.path_bypass["Demo Planning KC /auth/*"].priority == 2
      && length([for key in keys(pangolin_resource_rule.path_bypass) : key if startswith(key, "Flip Planning ")]) == 1
      && length([for key in keys(pangolin_resource_rule.path_bypass) : key if startswith(key, "Demo Planning /")]) == 1
      && length([for key in keys(pangolin_resource_rule.path_bypass) : key if startswith(key, "Demo Planning KC ")]) == 1
    )
    error_message = "Le contournement doit se limiter à /mcp/* (planning) et /auth/* (Keycloak du banc KC), en priorité 2."
  }

  # Les listes publiques de Karakeep se lisent sans compte et de partout :
  # devant les règles pays, et rien de plus large que ce que la page charge.
  # Un `/api/*` ouvrirait toute l'API sans le mur SSO ni le filtre pays. Les
  # priorités 2 à 6 sont celles des anciennes règles autonomes : le passage à
  # local.path_bypasses ne les a pas renumérotées.
  assert {
    condition = {
      for key, rule in pangolin_resource_rule.path_bypass :
      rule.value => rule.priority if startswith(key, "Karakeep ")
      } == {
      "/public/lists/*"                                    = 2
      "/_next/static/*"                                    = 3
      "/api/public/*"                                      = 4
      "/api/trpc/publicBookmarks.getPublicBookmarksInList" = 5
      "/api/v1/rss/lists/*"                                = 6
    }
    error_message = "Le contournement de Karakeep doit se limiter à ce que charge une liste publique (page, build Next.js, assets signés, tRPC getPublicBookmarksInList, RSS des listes), aux priorités 2 à 6."
  }

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

  # MCP de TREK : `/mcp` en PASS (saute les règles pays, garde l'authentification
  # Pangolin : SSO ou jeton d'accès), la surface publique d'OAuth en ACCEPT.
  # Tout en chemins exacts, avant les règles pays.
  assert {
    condition = (
      pangolin_resource_rule.trek_mcp.action == "PASS"
      && pangolin_resource_rule.trek_mcp.match == "PATH"
      && pangolin_resource_rule.trek_mcp.value == "/mcp"
      && pangolin_resource_rule.trek_mcp.enabled == true
      && pangolin_resource_rule.trek_mcp.priority >= 2 && pangolin_resource_rule.trek_mcp.priority < 10
    )
    error_message = "/mcp de TREK doit être un PASS (pas un ACCEPT) sur le chemin exact, avant les règles pays : le jeton d'accès Pangolin reste exigé."
  }

  # Ni l'enregistrement dynamique, ni l'autorisation (navigateur de
  # l'utilisateur, derrière le SSO), ni rien de l'API ou de l'interface : la
  # surface OAuth est la seule ouverture de TREK en priorité 2, sur des
  # chemins exacts.
  assert {
    condition = toset([
      for key, rule in pangolin_resource_rule.path_bypass :
      rule.value if startswith(key, "TREK ") && rule.priority == 2
      ]) == toset([
      "/.well-known/oauth-protected-resource/mcp",
      "/.well-known/oauth-protected-resource",
      "/.well-known/oauth-authorization-server",
      "/.well-known/oauth-authorization-server/mcp",
      "/.well-known/openid-configuration",
      "/mcp/.well-known/oauth-protected-resource",
      "/mcp/.well-known/oauth-authorization-server",
      "/mcp/.well-known/openid-configuration",
      "/oauth/token",
    ])
    error_message = "L'ouverture OAuth de TREK doit se limiter aux documents de découverte et à /oauth/token, en priorité 2."
  }

  assert {
    condition = alltrue([
      for key, rule in pangolin_resource_rule.path_bypass :
      !strcontains(rule.value, "*") if startswith(key, "TREK ") && rule.priority == 2
    ])
    error_message = "La surface OAuth de TREK : des chemins exacts, sans joker."
  }

  # L'override donne le même identifiant à toutes les instances d'une règle
  # for_each : l'audit d'inventaire ne verrait pas qu'une d'elles manque à
  # declared_extra_rules. D'où une comparaison sur les chemins, connus au plan.
  assert {
    condition = alltrue([
      for rule in concat(
        values(pangolin_resource_rule.path_bypass),
        values(pangolin_resource_rule.backslash_guard),
        [pangolin_resource_rule.trek_mcp],
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
      "Meerkat CRM /carddav/*",
      "Meerkat CRM /.well-known/carddav",
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
      "Paperless-ngx /share/*",
      "RSS /api/greader.php/*",
      "RSS /api/fever.php",
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
    ])
    error_message = "Les chemins ouverts sans SSO ont changé : relire la liste dans website_<app>.tf et la mettre à jour ici."
  }

  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.path_bypass :
      rule.action == "ACCEPT" && rule.match == "PATH" && rule.enabled == true
      && rule.priority >= 2 && rule.priority < 10
    ])
    error_message = "Les ouvertures par chemin sont des ACCEPT PATH dans la bande 2 à 9 : derrière le DROP antislash (1), devant les règles pays (10)."
  }

  # Aucune ouverture ne doit rendre une interface d'administration ou d'API
  # entière : ni racine, ni `/api/*`, ni `/i/*` de FreshRSS.
  assert {
    condition = alltrue([
      for rule in pangolin_resource_rule.path_bypass :
      !contains(["/*", "/api/*", "/api/v1/*", "/i/*", "/p/*"], rule.value)
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
# case, donc évalué avant toutes les autres.
run "backslash_guard_covers_every_path_rule" {
  command = plan

  assert {
    condition = toset(keys(pangolin_resource_rule.backslash_guard)) == toset([
      "Dawarich", "Demo Planning", "Demo Planning KC", "Flip Planning",
      "Karakeep", "Meerkat CRM", "Monica CRM", "nextcloud", "Paperless-ngx", "RSS", "TREK",
    ])
    error_message = "Toute ressource qui a une règle par chemin doit avoir son DROP antislash (local.backslash_guarded_resources)."
  }

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
        [pangolin_resource_rule.trek_mcp],
        values(pangolin_resource_rule.path_bypass),
      ) : rule.priority > 1
    ])
    error_message = "La priorité 1 est réservée au DROP antislash : une règle par chemin à égalité avec lui serait évaluée dans un ordre arbitraire."
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

# Karakeep reste derrière le mur SSO et le filtre pays : ses clients (app
# mobile, extension, MCP) passent avec un jeton d'accès Pangolin chacun, pas
# par un contournement de chemin (seules les listes publiques en ont un, voir
# bypass_rules_sit_in_their_priority_band). Un jeton par client, pour en
# révoquer un seul (téléphone perdu) sans toucher aux autres.
run "karakeep_clients_use_access_tokens_not_a_bypass" {
  command = plan

  assert {
    condition     = pangolin_resource.website["karakeep"].sso == true
    error_message = "Karakeep doit rester derrière le mur SSO de Pangolin."
  }

  assert {
    condition     = toset(keys(pangolin_resource_access_token.karakeep_clients)) == toset(["mobile", "extension", "mcp"])
    error_message = "Un jeton d'accès Pangolin par client de Karakeep : mobile, extension, mcp."
  }

  assert {
    condition = alltrue([
      for token in pangolin_resource_access_token.karakeep_clients :
      token.resource_id == pangolin_resource.website["karakeep"].id
    ])
    error_message = "Les jetons des clients de Karakeep doivent viser la ressource Karakeep."
  }

  assert {
    condition     = length(distinct([for token in pangolin_resource_access_token.karakeep_clients : token.title])) == 3
    error_message = "Chaque jeton doit porter un titre distinct, pour savoir lequel révoquer."
  }
}

# Le MCP de TREK passe par un jeton d'accès Pangolin par client, pas par un
# ACCEPT : en-têtes pour les clients qui en envoient, `?p_token=` dans l'URL du
# connecteur pour Claude.ai.
run "trek_mcp_clients_use_access_tokens" {
  command = plan

  assert {
    condition     = pangolin_resource.website["trek"].sso == true
    error_message = "TREK doit rester derrière le mur SSO de Pangolin."
  }

  assert {
    condition     = toset(keys(pangolin_resource_access_token.trek_mcp_clients)) == toset(["claude-ai", "claude-code"])
    error_message = "Un jeton d'accès Pangolin par client MCP de TREK : claude-ai, claude-code."
  }

  assert {
    condition = alltrue([
      for token in pangolin_resource_access_token.trek_mcp_clients :
      token.resource_id == pangolin_resource.website["trek"].id
    ])
    error_message = "Les jetons des clients MCP doivent viser la ressource TREK."
  }

  assert {
    condition     = length(distinct([for token in pangolin_resource_access_token.trek_mcp_clients : token.title])) == 2
    error_message = "Chaque jeton doit porter un titre distinct, pour savoir lequel révoquer."
  }
}

# Le format `?p_token=<id>.<jeton>` est celui que Pangolin découpe sur le point
# (verifySession.ts) ; un autre séparateur et le jeton ne serait jamais lu.
run "trek_mcp_connector_url_carries_the_token" {
  command = apply

  assert {
    condition = alltrue([
      for client in ["claude-ai", "claude-code"] :
      output.trek_mcp_client_access_tokens[client].connector_url == "https://travels.sylvain.cloud/mcp?p_token=tok-trek-mcp.jeton-trek-mcp"
      && output.trek_mcp_client_access_tokens[client].headers["P-Access-Token-Id"] == "tok-trek-mcp"
      && output.trek_mcp_client_access_tokens[client].headers["P-Access-Token"] == "jeton-trek-mcp"
    ])
    error_message = "L'URL de connecteur doit être https://<domaine>/mcp?p_token=<id>.<jeton>."
  }
}

# Les chemins publics de Karakeep (website_karakeep.tf) ont été relevés dans
# les sources de la v0.33.2. Une montée de version (Renovate) fait échouer ce
# run : relire apps/web/app/public, apps/web/components/public/lists et
# packages/api de la nouvelle version, ajuster karakeep_public_paths, puis la
# version ci-dessous.
run "karakeep_public_paths_follow_the_image" {
  command = plan

  assert {
    # Le tag seul : un épinglage du digest par Renovate (`:0.33.2@sha256:...`)
    # ne change pas la version et ne doit pas faire échouer ce run.
    condition     = length(regexall("image: ghcr\\.io/karakeep-app/karakeep:0\\.33\\.2(@|\\s)", file("${path.module}/../../ansible/roles/karakeep/templates/compose.yaml"))) == 1
    error_message = "Karakeep n'est plus en 0.33.2 : relire dans les sources de la nouvelle version les chemins que charge /public/lists/<id> et mettre à jour karakeep_public_paths (website_karakeep.tf) avant cette version."
  }
}

# Même garde-fou que pour Karakeep, pour chaque liste de local.path_bypasses :
# ces chemins ont été relus dans les sources d'UNE version de l'image. Quand
# Renovate la monte, une nouvelle route non authentifiée sous un préfixe ouvert
# (ou un partage déplacé) changerait en silence ce qui répond au monde entier
# sans SSO. Le tag seul est comparé : l'épinglage du digest ne compte pas.
run "path_bypasses_follow_their_image" {
  command = plan

  assert {
    condition = alltrue([
      for app, pin in {
        "TREK (website_trek.tf)"               = { file = "trek", image = "docker\\.io/mauriceboe/trek:4\\.3\\.3" }
        "Dawarich (website_dawarich.tf)"       = { file = "dawarich", image = "freikin/dawarich:1\\.15\\.3" }
        "Paperless-ngx (website_paperless.tf)" = { file = "paperless_ngx", image = "ghcr\\.io/paperless-ngx/paperless-ngx:3\\.2" }
        "FreshRSS (website_rss.tf)"            = { file = "rss", image = "freshrss/freshrss:1\\.30\\.0" }
        "Monica (website_monica.tf)"           = { file = "monica_v4", image = "monica:3\\.7\\.0-apache" }
        "Meerkat CRM (website_meerkat_crm.tf)" = { file = "meerkat_crm", image = "ghcr\\.io/fbuchner/meerkat-crm-backend:1\\.7\\.0" }
      } :
      length(regexall("image: ${pin.image}(@|\\s)", file("${path.module}/../../ansible/roles/${pin.file}/templates/compose.yaml"))) >= 1
    ])
    error_message = "Une image dont les chemins sont ouverts par local.path_bypasses a changé de version : relire dans les sources de la nouvelle version les routes sous les préfixes ouverts, mettre à jour la liste de chemins de l'app, puis la version attendue ici."
  }
}

# apply_rules = false laisse les règles pays en place mais Pangolin ne les
# évalue pas : NAS et Proxmox ont ainsi répondu de partout, derrière le seul
# SSO, pendant que rules.tf affichait leurs règles. Toute ressource publique
# applique donc les siennes, et seule Betisier se passe du SSO. Nextcloud l'a
# rejoint : ses clients et ses liens de partage passent par des chemins ouverts
# (website_nextcloud.tf), plus par une ressource entière sans SSO.
run "every_public_resource_applies_its_rules" {
  command = plan

  assert {
    condition     = alltrue([for r in pangolin_resource.website : r.apply_rules == true])
    error_message = "Une ressource publique a apply_rules = false : ses règles pays existent mais ne sont pas évaluées."
  }

  # Une ressource sans SSO n'a que son application pour la protéger. La liste
  # est fermée : en ajouter une est une décision, pas un oubli.
  assert {
    condition     = toset([for r in pangolin_resource.website : r.name if r.sso == false]) == toset(["Betisier"])
    error_message = "La seule ressource sans SSO doit être Betisier."
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
      && length(pangolin_resource.website) == 21
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

  # Une seule dérogation, écrite en clair dans website_gramps.tf : Gramps est
  # arrêté, sa ressource désactivée.
  assert {
    condition = alltrue([
      for key, r in pangolin_resource.website :
      r.mode == local.resource_pins.mode
      && r.ssl == local.resource_pins.ssl
      && r.enabled == (key == "gramps" ? r.enabled : local.resource_pins.enabled)
      && r.block_access == local.resource_pins.block_access
      && r.email_whitelist_enabled == local.resource_pins.email_whitelist_enabled
      && r.sticky_session == local.resource_pins.sticky_session
    ])
    error_message = "Une ressource Pangolin ne suit pas local.resource_pins (mode, ssl, enabled...), ou y déroge sans être Gramps."
  }

  # La ressource suit l'état du service côté Ansible : désactivée tant que
  # gramps_enabled est false, à réactiver avec lui.
  assert {
    condition = (
      local.resource_pins.enabled == true
      && pangolin_resource.website["gramps"].enabled == !strcontains(
        file("${path.module}/../../ansible/host_vars/docker/variables.yaml"),
        "\ngramps_enabled: false\n"
      )
    )
    error_message = "L'entrée gramps de local.websites doit suivre gramps_enabled (ansible/host_vars/docker/variables.yaml), et toutes les autres ressources rester actives."
  }
}

# Deux ressources sur le même FQDN se marcheraient dessus dans Traefik ; les
# environnements de Flip Planning sont chacun sur leur domaine.
run "resources_have_unique_fqdns_on_the_right_domains" {
  command = plan

  assert {
    condition = length(distinct([
      for r in pangolin_resource.website : "${r.subdomain == null ? "@" : r.subdomain}.${r.domain_id}"
    ])) == length(local.managed_resources)
    error_message = "Deux ressources Pangolin partagent le même sous-domaine sur le même domaine."
  }

  assert {
    condition     = pangolin_resource.website["flip_planning"].domain_id == "dom-cloud" && pangolin_resource.website["flip_planning"].subdomain == "flip-planning"
    error_message = "La production de Flip Planning est servie sur flip-planning.sylvain.cloud."
  }

  assert {
    condition = (
      pangolin_resource.website["demo_planning"].domain_id == "dom-dev" && pangolin_resource.website["demo_planning"].subdomain == "demo-planning"
      && pangolin_resource.website["demo_planning_kc"].domain_id == "dom-dev" && pangolin_resource.website["demo_planning_kc"].subdomain == "demo-planning-kc"
    )
    error_message = "Les démos de Flip Planning sont servies sur sylvain.dev (demo-planning, demo-planning-kc)."
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

  # Un moniteur actif sur une ressource désactivée ne pourrait qu'être DOWN et
  # écrire : Gramps, arrêté, a les deux siens inactifs.
  assert {
    condition = alltrue([
      for key, m in uptimekuma_monitor_http_keyword.healthcheck :
      m.active == (key != "gramps")
    ])
    error_message = "Tous les healthchecks sont actifs, sauf celui de Gramps, arrêté."
  }

  # Les noms de moniteurs n'ont pas bougé avec la factorisation : Uptime Kuma
  # les affiche, et les mails d'alerte les citent.
  assert {
    condition = alltrue([
      for key, m in uptimekuma_monitor_http_keyword.healthcheck :
      m.name == "Healthcheck ${local.websites[key].name}"
    ])
    error_message = "Un healthcheck ne s'appelle plus « Healthcheck <nom de la ressource> »."
  }
}

# Le dashboard Pangolin et ref.sylvain.dev ont leur moniteur. L'URL du
# dashboard est celle que publie le rôle pangolin (host_vars/pangolin) : un
# renommage d'un seul côté laisserait le moniteur sonder un nom mort. Pas de
# mot-clé inversé ici : ni l'un ni l'autre n'est une ressource Pangolin, donc
# pas de page de maintenance à reconnaître.
run "pangolin_dashboard_and_ref_are_monitored" {
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

  assert {
    condition     = uptimekuma_monitor_http.ref.url == "https://ref.sylvain.dev" && uptimekuma_monitor_http.ref.active == true
    error_message = "ref.sylvain.dev (tofu/ref) doit avoir son moniteur actif."
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
  # Betisier (sans SSO), NAS et Proxmox (l'administrateur seul). Immich Swipe
  # prend celui d'Immich.
  assert {
    condition = (
      setsubtract(toset(keys(local.websites)), keys(pangolin_resource_role.website)) == toset(["betisier", "nas", "proxmox"])
      && local.websites["immich_swipe"].role == "immich"
    )
    error_message = "Chaque application derrière le SSO est liée à son rôle (Immich Swipe à celui d'Immich), sauf NAS et Proxmox."
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

  assert {
    condition = (
      pangolin_resource_rule.path_bypass["Flip Planning /mcp/*"].resource_id == pangolin_resource.website["flip_planning"].id
      && pangolin_resource_rule.path_bypass["Demo Planning /mcp/*"].resource_id == pangolin_resource.website["demo_planning"].id
      && pangolin_resource_rule.path_bypass["Demo Planning KC /auth/*"].resource_id == pangolin_resource.website["demo_planning_kc"].id
      && pangolin_resource_rule.immich_home_ip.resource_id == pangolin_resource.website["immich"].id
      && pangolin_resource_rule.dawarich_home_ip.resource_id == pangolin_resource.website["dawarich"].id
      && pangolin_resource_rule.trek_home_ip.resource_id == pangolin_resource.website["trek"].id
      && pangolin_resource_rule.backslash_guard["Karakeep"].resource_id == pangolin_resource.website["karakeep"].id
      && pangolin_resource_rule.backslash_guard["TREK"].resource_id == pangolin_resource.website["trek"].id
      && pangolin_resource_rule.path_bypass["TREK /public/journey/*"].resource_id == pangolin_resource.website["trek"].id
      && pangolin_resource_rule.path_bypass["Paperless-ngx /share/*"].resource_id == pangolin_resource.website["paperless"].id
      && pangolin_resource_rule.path_bypass["Dawarich /s/*"].resource_id == pangolin_resource.website["dawarich"].id
      && pangolin_resource_rule.path_bypass["RSS /api/fever.php"].resource_id == pangolin_resource.website["rss"].id
      && pangolin_resource_rule.path_bypass["Monica CRM /dav/*"].resource_id == pangolin_resource.website["monica"].id
      && pangolin_resource_rule.path_bypass["Meerkat CRM /carddav/*"].resource_id == pangolin_resource.website["meerkat_crm"].id
      && pangolin_resource_rule.path_bypass["nextcloud /remote.php/*"].resource_id == pangolin_resource.website["nextcloud"].id
      && pangolin_resource_rule.backslash_guard["nextcloud"].resource_id == pangolin_resource.website["nextcloud"].id
      && pangolin_resource_rule.trek_mcp.resource_id == pangolin_resource.website["trek"].id
      && alltrue([
        for key, rule in pangolin_resource_rule.path_bypass :
        rule.resource_id == pangolin_resource.website["trek"].id if startswith(key, "TREK ")
      ])
      && alltrue([
        for key, rule in pangolin_resource_rule.path_bypass :
        rule.resource_id == pangolin_resource.website["karakeep"].id if startswith(key, "Karakeep ")
      ])
    )
    error_message = "Une règle spécifique est rattachée à la mauvaise ressource."
  }
}

# Les sorties lues par les playbooks (`terraform_outputs.<nom>.value |
# default('')`) : une sortie renommée ou supprimée donne une chaîne vide sans
# erreur, et la sauvegarde ne signale plus jamais rien. Chacune doit exister et
# pointer sur le jeton de SON moniteur push.
run "outputs_read_by_ansible_point_at_their_own_push_monitor" {
  command = apply

  # docker.yml
  assert {
    condition     = output.uptime_backup_nextcloud_url == "https://uptime.example.test/api/push/push-nextcloud"
    error_message = "uptime_backup_nextcloud_url (docker.yml) ne pointe pas sur le moniteur Backup nextcloud."
  }

  assert {
    condition     = output.uptime_backup_wiki_url == "https://uptime.example.test/api/push/push-wiki"
    error_message = "uptime_backup_wiki_url (docker.yml) ne pointe pas sur le moniteur Backup wiki."
  }

  assert {
    condition     = output.uptime_backup_rss_url == "https://uptime.example.test/api/push/push-rss"
    error_message = "uptime_backup_rss_url (docker.yml) ne pointe pas sur le moniteur Backup RSS."
  }

  assert {
    condition     = output.uptime_backup_monica_url == "https://uptime.example.test/api/push/push-monica"
    error_message = "uptime_backup_monica_url (docker.yml) ne pointe pas sur le moniteur Backup Monica."
  }

  assert {
    condition     = output.uptime_cron_monica_url == "https://uptime.example.test/api/push/push-cron-monica"
    error_message = "uptime_cron_monica_url (docker.yml) ne pointe pas sur le moniteur Cron Monica."
  }

  assert {
    condition     = output.uptime_backup_betisier_url == "https://uptime.example.test/api/push/push-betisier"
    error_message = "uptime_backup_betisier_url (docker.yml) ne pointe pas sur le moniteur Backup Betisier."
  }

  assert {
    condition     = output.uptime_backup_meerkat_crm_url == "https://uptime.example.test/api/push/push-meerkat-crm"
    error_message = "uptime_backup_meerkat_crm_url (docker.yml) ne pointe pas sur le moniteur Backup Meerkat CRM."
  }

  assert {
    condition     = output.uptime_backup_gramps_url == "https://uptime.example.test/api/push/push-gramps"
    error_message = "uptime_backup_gramps_url (docker.yml) ne pointe pas sur le moniteur Backup Gramps."
  }

  assert {
    condition     = output.uptime_backup_dawarich_url == "https://uptime.example.test/api/push/push-dawarich"
    error_message = "uptime_backup_dawarich_url (docker.yml) ne pointe pas sur le moniteur Backup Dawarich."
  }

  assert {
    condition     = output.uptime_backup_scanopy_url == "https://uptime.example.test/api/push/push-scanopy"
    error_message = "uptime_backup_scanopy_url (docker.yml) ne pointe pas sur le moniteur Backup Scanopy."
  }

  assert {
    condition     = output.uptime_backup_trek_url == "https://uptime.example.test/api/push/push-trek"
    error_message = "uptime_backup_trek_url (docker.yml) ne pointe pas sur le moniteur Backup TREK."
  }

  assert {
    condition     = output.uptime_backup_karakeep_url == "https://uptime.example.test/api/push/push-karakeep"
    error_message = "uptime_backup_karakeep_url (docker.yml) ne pointe pas sur le moniteur Backup Karakeep."
  }

  assert {
    condition     = output.uptime_backup_searxng_url == "https://uptime.example.test/api/push/push-searxng"
    error_message = "uptime_backup_searxng_url (docker.yml) ne pointe pas sur le moniteur Backup SearXNG."
  }

  assert {
    condition     = output.uptime_backup_paperless_url == "https://uptime.example.test/api/push/push-paperless"
    error_message = "uptime_backup_paperless_url (docker.yml) ne pointe pas sur le moniteur Backup Paperless."
  }

  # flip.yml
  assert {
    condition     = output.uptime_backup_flip_planning_url == "https://uptime.example.test/api/push/push-flip-planning"
    error_message = "uptime_backup_flip_planning_url (flip.yml, instance de production) ne pointe pas sur le moniteur Backup Flip Planning."
  }

  assert {
    condition     = output.uptime_backup_demo_planning_url == "https://uptime.example.test/api/push/push-demo-planning"
    error_message = "uptime_backup_demo_planning_url (flip.yml, instance de démo) ne pointe pas sur le moniteur Backup Demo Planning."
  }

  # pi.yml
  assert {
    condition     = output.uptime_backup_immich_url == "https://uptime.example.test/api/push/push-immich"
    error_message = "uptime_backup_immich_url (pi.yml) ne pointe pas sur le moniteur Backup Immich."
  }

  # pangolin.yaml
  assert {
    condition     = output.uptime_backup_pangolin_url == "https://uptime.example.test/api/push/push-pangolin"
    error_message = "uptime_backup_pangolin_url (pangolin.yaml) ne pointe pas sur le moniteur Backup Pangolin."
  }

  # Deux playbooks qui poussent sur le même moniteur se masquent l'un l'autre.
  # Comparé au nombre de sorties uptime_*_url du module, pas à un compte en
  # dur : une sortie ajoutée sans être listée ici fait aussi échouer le run.
  assert {
    condition = length(distinct([
      output.uptime_backup_nextcloud_url,
      output.uptime_backup_wiki_url,
      output.uptime_backup_rss_url,
      output.uptime_backup_monica_url,
      output.uptime_cron_monica_url,
      output.uptime_backup_betisier_url,
      output.uptime_backup_meerkat_crm_url,
      output.uptime_backup_gramps_url,
      output.uptime_backup_dawarich_url,
      output.uptime_backup_scanopy_url,
      output.uptime_backup_trek_url,
      output.uptime_backup_karakeep_url,
      output.uptime_backup_searxng_url,
      output.uptime_backup_paperless_url,
      output.uptime_backup_flip_planning_url,
      output.uptime_backup_demo_planning_url,
      output.uptime_backup_immich_url,
      output.uptime_backup_pangolin_url,
      ])) == length(flatten([
      for f in fileset(path.module, "*.tf") :
      regexall("output \"uptime_(?:backup|cron)_\\w+_url\"", file("${path.module}/${f}"))
    ]))
    error_message = "Deux sorties lues par Ansible pointent sur le même moniteur push, ou une sortie uptime_*_url manque à cette liste."
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
        for playbook in ["docker.yml", "flip.yml", "pi.yml", "pangolin.yaml"] :
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
      && pangolin_site_resource.flip.udp_port_range == ""
    )
    error_message = "flip.internal doit viser l'IP privée de flip (remote state), sur le site flip, en TCP 22 uniquement."
  }
}

# Production et démo partagent un rôle Ansible mais rien côté Pangolin /
# Uptime Kuma : ressource, jeton d'accès, healthcheck, moniteur de sauvegarde,
# règle MCP et cibles sont distincts, et chaque cible vise les conteneurs de
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
      uptimekuma_monitor_http_keyword.healthcheck["flip_planning"].url == "https://flip-planning.sylvain.cloud"
      && uptimekuma_monitor_http_keyword.healthcheck["demo_planning"].url == "https://demo-planning.sylvain.dev"
    )
    error_message = "Chaque healthcheck doit sonder le FQDN de son environnement."
  }

  assert {
    condition = (
      jsondecode(output.flip_planning_access_token).token == "jeton-flip-planning"
      && jsondecode(output.demo_planning_access_token).token == "jeton-demo-planning"
    )
    error_message = "Les sorties *_access_token doivent exposer le jeton de leur propre environnement."
  }

  assert {
    condition = (
      uptimekuma_monitor_push.backup["flip_planning"].name == "Backup Flip Planning"
      && uptimekuma_monitor_push.backup["demo_planning"].name == "Backup Demo Planning"
    )
    error_message = "Chaque environnement doit avoir son propre moniteur de sauvegarde."
  }

  assert {
    condition = (
      pangolin_resource_role.website["flip_planning"].resource_id == pangolin_resource.website["flip_planning"].id
      && pangolin_resource_role.website["demo_planning"].resource_id == pangolin_resource.website["demo_planning"].id
      && pangolin_resource_role.website["demo_planning_kc"].resource_id == pangolin_resource.website["demo_planning_kc"].id
    )
    error_message = "Chaque ressource de Flip Planning porte sa propre liaison de rôle."
  }

  assert {
    condition = alltrue([
      for r in [pangolin_resource.website["flip_planning"], pangolin_resource.website["demo_planning"], pangolin_resource.website["demo_planning_kc"]] :
      r.sso == true && r.apply_rules == true && r.enabled == true
    ])
    error_message = "Les trois environnements de Flip Planning restent derrière le SSO, avec les règles appliquées."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.website["flip_planning"],
        pangolin_target.website["flip_planning_pgadmin"],
        pangolin_target.website["flip_planning_mailpit"],
        pangolin_target.website["flip_planning_assets"],
      ] : t.resource_id == pangolin_resource.website["flip_planning"].id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles de production doivent appartenir à la ressource Flip Planning, sur le site flip."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.website["demo_planning"],
        pangolin_target.website["demo_planning_pgadmin"],
        pangolin_target.website["demo_planning_mailpit"],
        pangolin_target.website["demo_planning_assets"],
      ] : t.resource_id == pangolin_resource.website["demo_planning"].id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles de démo doivent appartenir à la ressource Demo Planning, sur le site flip."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.website["demo_planning_kc"],
        pangolin_target.website["demo_planning_kc_pgadmin"],
        pangolin_target.website["demo_planning_kc_mailpit"],
        pangolin_target.website["demo_planning_kc_assets"],
        pangolin_target.website["demo_planning_kc_keycloak"],
      ] : t.resource_id == pangolin_resource.website["demo_planning_kc"].id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles du banc KC doivent appartenir à la ressource Demo Planning KC, sur le site flip."
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
# Backup avec un battement quotidien, chaque healthcheck dans Self-hosted, et
# tous reliés au canal e-mail (un moniteur sans notification ne prévient
# personne, comme gramps et scanopy en 503 pendant des heures). Tout moniteur
# de sauvegarde est actif, sauf celui de Gramps, arrêté (website_gramps.tf) :
# l'exception est nommée, et le test échoue aussi s'il redevient actif sans
# qu'on la retire.
run "monitors_are_filed_and_notify_by_email" {
  command = apply

  # Les moniteurs de sauvegarde sont les instances de
  # uptimekuma_monitor_push.backup (entrées `backup = true` de local.websites),
  # plus celui de Pangolin. Les clés sont épinglées : en ajouter ou en retirer
  # un est une décision, et chacune garde l'adresse que moved.tf lui a donnée.
  assert {
    condition = toset(keys(uptimekuma_monitor_push.backup)) == toset([
      "betisier", "dawarich", "demo_planning", "flip_planning", "gramps", "immich", "karakeep",
      "meerkat_crm", "monica", "nextcloud", "paperless", "rss", "scanopy", "searxng", "trek", "wiki",
    ])
    error_message = "Les moniteurs de sauvegarde ont changé : relire les champs backup de local.websites."
  }

  assert {
    condition = alltrue([
      for m in concat(values(uptimekuma_monitor_push.backup), [uptimekuma_monitor_push.backup_pangolin]) :
      m.parent == uptimekuma_monitor_group.backups.id
      && m.interval == 86400
      && m.active == true
      && contains(m.notification_ids, uptimekuma_notification_smtp.email.id)
    ])
    error_message = "Chaque moniteur de sauvegarde doit être dans le dossier Backup, quotidien, actif (sauf Gramps, arrêté) et notifié par e-mail."
  }

  # Les noms n'ont pas bougé avec la factorisation : « Backup <ressource> ».
  assert {
    condition = alltrue([
      for key, m in uptimekuma_monitor_push.backup :
      m.name == "Backup ${local.websites[key].name}"
    ])
    error_message = "Un moniteur de sauvegarde ne s'appelle plus « Backup <nom de la ressource> »."
  }

  assert {
    condition = (
      uptimekuma_monitor_push.cron_monica.parent == uptimekuma_monitor_group.self_hosted.id
      && contains(uptimekuma_monitor_push.cron_monica.notification_ids, uptimekuma_notification_smtp.email.id)
    )
    error_message = "Le cron de Monica n'est pas une sauvegarde : il est rangé avec les healthchecks et notifié par e-mail."
  }

  assert {
    condition = alltrue([
      for m in concat(values(uptimekuma_monitor_http_keyword.healthcheck), [uptimekuma_monitor_http.pangolin_dashboard]) :
      m.parent == uptimekuma_monitor_group.self_hosted.id
      && contains(m.notification_ids, uptimekuma_notification_smtp.email.id)
    ])
    error_message = "Chaque healthcheck doit être dans le dossier Self-hosted et notifié par e-mail."
  }

  assert {
    condition = (
      uptimekuma_notification_smtp.email.is_default == true
      && uptimekuma_notification_smtp.email.apply_existing == false
      && uptimekuma_notification_smtp.email.to == "admin@example.test"
    )
    error_message = "Le canal e-mail est le canal par défaut, n'est pas rattaché en masse, et écrit à l'adresse Let's Encrypt (le_email)."
  }
}
