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

# --- Réponses réalistes de l'API Pangolin (cas nominal) ---------------------

# GET /v1/org/{org}/resources?pageSize=1000 : les 22 ressources gérées, la
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
      ], "pagination": {"total": 24, "pageSize": 1000, "page": 1}},
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
# six règles spécifiques : si l'une d'elles disparaît de
# local.declared_extra_rules, le run nominal échoue.
override_data {
  target = data.http.pangolin_rules
  values = {
    status_code   = 200
    response_body = <<-EOT
      {"data": {"rules": [
        {"ruleId": 2001, "action": "ACCEPT", "match": "PATH", "value": "/mcp/*", "priority": 1, "enabled": true},
        {"ruleId": 2002, "action": "ACCEPT", "match": "PATH", "value": "/mcp/*", "priority": 1, "enabled": true},
        {"ruleId": 2003, "action": "ACCEPT", "match": "PATH", "value": "/auth/*", "priority": 2, "enabled": true},
        {"ruleId": 1010, "action": "PASS", "match": "COUNTRY", "value": "FR", "priority": 10, "enabled": true},
        {"ruleId": 2004, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 2005, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 2006, "action": "ACCEPT", "match": "IP", "value": "203.0.113.10", "priority": 12, "enabled": true},
        {"ruleId": 1099, "action": "DROP", "match": "COUNTRY", "value": "ALL", "priority": 99, "enabled": true}
      ], "pagination": {"total": 8, "pageSize": 1000, "page": 1}},
      "success": true, "error": false, "message": "Rules retrieved successfully", "status": 200}
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

# Ressources publiques : un identifiant par ressource, ceux de l'API quand un
# commentaire du code les cite (Traefik 2, Proxmox 4, BBOX 15, NAS 75).
override_resource {
  target = pangolin_resource.bbox
  values = { id = 15 }
}

override_resource {
  target = pangolin_resource.betisier
  values = { id = 21 }
}

override_resource {
  target = pangolin_resource.traefik_dashboard
  values = { id = 2 }
}

override_resource {
  target = pangolin_resource.dawarich
  values = { id = 60 }
}

override_resource {
  target = pangolin_resource.demo_planning
  values = { id = 81, full_domain = "demo-planning.sylvain.dev" }
}

override_resource {
  target = pangolin_resource.demo_planning_kc
  values = { id = 82, full_domain = "demo-planning-kc.sylvain.dev" }
}

override_resource {
  target = pangolin_resource.echo
  values = { id = 22 }
}

override_resource {
  target = pangolin_resource.flip_planning
  values = { id = 80, full_domain = "flip-planning.sylvain.cloud" }
}

override_resource {
  target = pangolin_resource.gramps
  values = { id = 55 }
}

override_resource {
  target = pangolin_resource.immich
  values = { id = 10 }
}

override_resource {
  target = pangolin_resource.immich_swipe
  values = { id = 23 }
}

override_resource {
  target = pangolin_resource.meerkat_crm
  values = { id = 30 }
}

override_resource {
  target = pangolin_resource.monica
  values = { id = 31 }
}

override_resource {
  target = pangolin_resource.nas
  values = { id = 75 }
}

override_resource {
  target = pangolin_resource.nextcloud
  values = { id = 11 }
}

override_resource {
  target = pangolin_resource.paperless
  values = { id = 40 }
}

override_resource {
  target = pangolin_resource.proxmox
  values = { id = 4 }
}

override_resource {
  target = pangolin_resource.rss
  values = { id = 32 }
}

override_resource {
  target = pangolin_resource.scanopy
  values = { id = 56 }
}

override_resource {
  target = pangolin_resource.searxng
  values = { id = 41 }
}

override_resource {
  target = pangolin_resource.trek
  values = { id = 61 }
}

override_resource {
  target = pangolin_resource.wiki
  values = { id = 33 }
}

# Jetons d'accès des healthchecks de Flip Planning : un par environnement.
override_resource {
  target = pangolin_resource_access_token.flip_planning
  values = { id = "tok-flip-planning", token = "jeton-flip-planning" }
}

override_resource {
  target = pangolin_resource_access_token.demo_planning
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

# Jetons push : un par moniteur, pour prouver que chaque sortie lue par Ansible
# pointe sur SON moniteur (la démo a déjà poussé sur celui de la production).
override_resource {
  target = uptimekuma_monitor_push.backup_betisier
  values = { push_token = "push-betisier" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_dawarich
  values = { push_token = "push-dawarich" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_demo_planning
  values = { push_token = "push-demo-planning" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_flip_planning
  values = { push_token = "push-flip-planning" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_gramps
  values = { push_token = "push-gramps" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_immich
  values = { push_token = "push-immich" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_meerkat_crm
  values = { push_token = "push-meerkat-crm" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_monica
  values = { push_token = "push-monica" }
}

override_resource {
  target = uptimekuma_monitor_push.cron_monica
  values = { push_token = "push-cron-monica" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_nextcloud
  values = { push_token = "push-nextcloud" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_pangolin
  values = { push_token = "push-pangolin" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_paperless
  values = { push_token = "push-paperless" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_rss
  values = { push_token = "push-rss" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_scanopy
  values = { push_token = "push-scanopy" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_searxng
  values = { push_token = "push-searxng" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_trek
  values = { push_token = "push-trek" }
}

override_resource {
  target = uptimekuma_monitor_push.backup_wiki
  values = { push_token = "push-wiki" }
}

# ===========================================================================
# Runs `plan` : valeurs issues de la configuration
# ===========================================================================

# Chaque cible sondée déclare hc_scheme / hc_mode / hc_port. Ils sont
# optionnels+calculés : non déclarés, Pangolin a stocké NULL pour gramps et
# scanopy, la sonde ne pouvait jamais réussir et les deux sites ont servi
# "no available server" pendant que `tofu plan` ne voyait rien.
run "every_probed_target_declares_scheme_mode_and_port" {
  command = plan

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.betisier,
        pangolin_target.dawarich,
        pangolin_target.demo_planning,
        pangolin_target.demo_planning_pgadmin,
        pangolin_target.demo_planning_mailpit,
        pangolin_target.demo_planning_assets,
        pangolin_target.demo_planning_kc,
        pangolin_target.demo_planning_kc_pgadmin,
        pangolin_target.demo_planning_kc_mailpit,
        pangolin_target.demo_planning_kc_assets,
        pangolin_target.demo_planning_kc_keycloak,
        pangolin_target.echo,
        pangolin_target.echo,
        pangolin_target.flip_planning,
        pangolin_target.flip_planning_pgadmin,
        pangolin_target.flip_planning_mailpit,
        pangolin_target.flip_planning_assets,
        pangolin_target.gramps,
        pangolin_target.immich,
        pangolin_target.immich_swipe,
        pangolin_target.meerkat_crm,
        pangolin_target.monica,
        pangolin_target.nextcloud,
        pangolin_target.immich,
        pangolin_target.immich_swipe,
        pangolin_target.meerkat_crm,
        pangolin_target.monica,
        pangolin_target.nextcloud,
        pangolin_target.paperless,
        pangolin_target.proxmox,
        pangolin_target.rss,
        pangolin_target.rss,
        pangolin_target.scanopy,
        pangolin_target.searxng,
        pangolin_target.trek,
        pangolin_target.wiki,
      ] :
      t.hc_enabled == true
      && contains(["http", "https"], t.hc_scheme)
      && t.hc_mode == "http"
      && t.hc_port != null
    ])
    error_message = "Une cible sondée n'a pas hc_scheme (http/https), hc_mode = \"http\" ou hc_port : Pangolin stockerait NULL et la sonde échouerait toujours."
  }
}

# hc_hostname explicite et égal à `ip` : la sonde envoie le bon Host au bon
# conteneur. Le provider ne le déduit pas de `ip`.
run "probed_targets_set_hc_hostname_to_their_ip" {
  command = plan

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.bbox,
        pangolin_target.betisier,
        pangolin_target.dawarich,
        pangolin_target.demo_planning,
        pangolin_target.demo_planning_pgadmin,
        pangolin_target.demo_planning_mailpit,
        pangolin_target.demo_planning_assets,
        pangolin_target.demo_planning_kc,
        pangolin_target.demo_planning_kc_pgadmin,
        pangolin_target.demo_planning_kc_mailpit,
        pangolin_target.demo_planning_kc_assets,
        pangolin_target.demo_planning_kc_keycloak,
        pangolin_target.flip_planning,
        pangolin_target.flip_planning_pgadmin,
        pangolin_target.flip_planning_mailpit,
        pangolin_target.flip_planning_assets,
        pangolin_target.gramps,
        pangolin_target.paperless,
        pangolin_target.proxmox,
        pangolin_target.scanopy,
        pangolin_target.searxng,
        pangolin_target.trek,
        pangolin_target.wiki,
      ] : t.hc_hostname == t.ip
    ])
    error_message = "Une cible a un hc_hostname absent ou différent de son ip."
  }

  # La liste ci-dessus ne voit pas une cible ajoutée plus tard : on vérifie
  # aussi, fichier par fichier, au moins autant de hc_hostname que de sondes
  # actives (bbox en garde un sur sa sonde désactivée).
  assert {
    condition = alltrue([
      for f in fileset(path.module, "website_*.tf") :
      length(regexall("hc_enabled\\s*=\\s*true", file("${path.module}/${f}")))
      <= length(regexall("hc_hostname\\s*=", file("${path.module}/${f}")))
    ]) && pangolin_target.trek.hc_hostname == pangolin_target.trek.ip
    error_message = "Un website_*.tf déclare une sonde (hc_enabled = true) sans hc_hostname."
  }
}

# Routage par chemin : la cible attrape-tout "/" doit avoir le numéro de
# priorité le PLUS BAS de sa ressource, sinon elle avale /db, /mail, /assets
# et /auth. Les priorités d'une même ressource sont toutes distinctes.
run "catch_all_target_has_lowest_priority" {
  command = plan

  assert {
    condition = (
      pangolin_target.flip_planning.path == "/"
      && alltrue([
        for t in [
          pangolin_target.flip_planning_pgadmin,
          pangolin_target.flip_planning_mailpit,
          pangolin_target.flip_planning_assets,
        ] : t.path != "/" && t.priority > pangolin_target.flip_planning.priority
      ])
    )
    error_message = "Flip Planning : la cible \"/\" doit avoir une priorité plus basse que /db, /mail et /assets."
  }

  assert {
    condition = (
      pangolin_target.demo_planning.path == "/"
      && alltrue([
        for t in [
          pangolin_target.demo_planning_pgadmin,
          pangolin_target.demo_planning_mailpit,
          pangolin_target.demo_planning_assets,
        ] : t.path != "/" && t.priority > pangolin_target.demo_planning.priority
      ])
    )
    error_message = "Demo Planning : la cible \"/\" doit avoir une priorité plus basse que /db, /mail et /assets."
  }

  assert {
    condition = (
      pangolin_target.demo_planning_kc.path == "/"
      && alltrue([
        for t in [
          pangolin_target.demo_planning_kc_pgadmin,
          pangolin_target.demo_planning_kc_mailpit,
          pangolin_target.demo_planning_kc_assets,
          pangolin_target.demo_planning_kc_keycloak,
        ] : t.path != "/" && t.priority > pangolin_target.demo_planning_kc.priority
      ])
    )
    error_message = "Demo Planning KC : la cible \"/\" doit avoir une priorité plus basse que /db, /mail, /assets et /auth."
  }

  assert {
    condition = alltrue([
      for group in [
        [
          pangolin_target.flip_planning,
          pangolin_target.flip_planning_pgadmin,
          pangolin_target.flip_planning_mailpit,
          pangolin_target.flip_planning_assets,
        ],
        [
          pangolin_target.demo_planning,
          pangolin_target.demo_planning_pgadmin,
          pangolin_target.demo_planning_mailpit,
          pangolin_target.demo_planning_assets,
        ],
        [
          pangolin_target.demo_planning_kc,
          pangolin_target.demo_planning_kc_pgadmin,
          pangolin_target.demo_planning_kc_mailpit,
          pangolin_target.demo_planning_kc_assets,
          pangolin_target.demo_planning_kc_keycloak,
        ],
      ] :
      length(distinct([for t in group : t.priority])) == length(group)
      && length(distinct([for t in group : t.path])) == length(group)
      && alltrue([for t in group : t.path_match_type == "prefix"])
    ])
    error_message = "Les cibles d'une même ressource multi-chemins doivent avoir des priorités et des chemins distincts, en correspondance par préfixe."
  }
}

# Les règles pays sont dérivées de la configuration : 22 ressources gérées plus
# SSH PI (épinglée), chacune avec PASS FR, PASS DE et DROP ALL.
run "country_rules_cover_every_resource" {
  command = plan

  assert {
    condition     = length(pangolin_resource_rule.block_country) == 23
    error_message = "Il faut une règle DROP COUNTRY ALL par ressource couverte (22 gérées + SSH PI)."
  }

  assert {
    condition     = length(pangolin_resource_rule.allow_countries) == 23 * 2
    error_message = "Il faut une règle PASS par ressource couverte et par pays autorisé (FR, DE)."
  }

  assert {
    condition = alltrue([
      for name in [
        "BBOX", "Betisier", "Dashboard Traefik", "Dawarich", "Demo Planning",
        "Demo Planning KC", "Echo", "Flip Planning", "Gramps", "Immich",
        "Immich Swipe", "Meerkat CRM", "Monica CRM", "NAS", "nextcloud",
        "Paperless-ngx", "Proxmox", "RSS", "Scanopy", "SearXNG", "TREK",
        "Wiki (Bookstack)", "SSH PI",
      ] :
      contains(keys(pangolin_resource_rule.block_country), name)
      && contains(keys(pangolin_resource_rule.allow_countries), "${name}-FR")
      && contains(keys(pangolin_resource_rule.allow_countries), "${name}-DE")
    ])
    error_message = "Une ressource publique n'a pas ses trois règles pays (PASS FR, PASS DE, DROP ALL)."
  }

  assert {
    condition     = pangolin_resource_rule.block_country["SSH PI"].resource_id == 38
    error_message = "SSH PI est épinglée par identifiant (38) dans local.unmanaged_resources."
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

# La bande de priorités de rules.tf : les ACCEPT qui doivent passer quelle que
# soit l'origine sont AVANT les PASS pays (1-9), les ACCEPT d'IP maison juste
# après (12), et le DROP ALL en dernier (99).
run "bypass_rules_sit_in_their_priority_band" {
  command = plan

  assert {
    condition = alltrue([
      for rule in [
        pangolin_resource_rule.flip_planning_mcp,
        pangolin_resource_rule.demo_planning_mcp,
        pangolin_resource_rule.demo_planning_kc_keycloak,
      ] :
      rule.action == "ACCEPT" && rule.match == "PATH" && rule.enabled == true
      && rule.priority >= 1 && rule.priority < 10
    ])
    error_message = "Les ACCEPT par chemin doivent être évalués avant les règles pays (priorités 1 à 9) : un PASS pays ne les laisserait jamais atteindre."
  }

  assert {
    condition = (
      pangolin_resource_rule.flip_planning_mcp.value == "/mcp/*"
      && pangolin_resource_rule.demo_planning_mcp.value == "/mcp/*"
      && pangolin_resource_rule.demo_planning_kc_keycloak.value == "/auth/*"
    )
    error_message = "Le contournement doit se limiter à /mcp/* (planning) et /auth/* (Keycloak du banc KC)."
  }

  assert {
    condition = alltrue([
      for rule in [
        pangolin_resource_rule.immich_home_ip,
        pangolin_resource_rule.dawarich_home_ip,
        pangolin_resource_rule.trek_home_ip,
      ] :
      rule.action == "ACCEPT" && rule.match == "IP" && rule.value == "203.0.113.10"
      && rule.priority == 12 && rule.enabled == true
    ])
    error_message = "Les ACCEPT de l'IP maison doivent être à la priorité 12, après les PASS pays (10-11) et avant le DROP (99)."
  }
}

# Deux ressources sur le même FQDN se marcheraient dessus dans Traefik ; les
# environnements de Flip Planning sont chacun sur leur domaine.
run "resources_have_unique_fqdns_on_the_right_domains" {
  command = plan

  assert {
    condition = length(distinct([
      for r in [
        pangolin_resource.bbox, pangolin_resource.betisier, pangolin_resource.traefik_dashboard,
        pangolin_resource.dawarich, pangolin_resource.demo_planning, pangolin_resource.demo_planning_kc,
        pangolin_resource.echo, pangolin_resource.flip_planning, pangolin_resource.gramps,
        pangolin_resource.immich, pangolin_resource.immich_swipe, pangolin_resource.meerkat_crm,
        pangolin_resource.monica, pangolin_resource.nas, pangolin_resource.nextcloud,
        pangolin_resource.paperless, pangolin_resource.proxmox, pangolin_resource.rss,
        pangolin_resource.scanopy, pangolin_resource.searxng, pangolin_resource.trek,
        pangolin_resource.wiki,
      ] : "${r.subdomain == null ? "@" : r.subdomain}.${r.domain_id}"
    ])) == 22
    error_message = "Deux ressources Pangolin partagent le même sous-domaine sur le même domaine."
  }

  assert {
    condition     = pangolin_resource.flip_planning.domain_id == "dom-cloud" && pangolin_resource.flip_planning.subdomain == "flip-planning"
    error_message = "La production de Flip Planning est servie sur flip-planning.sylvain.cloud."
  }

  assert {
    condition = (
      pangolin_resource.demo_planning.domain_id == "dom-dev" && pangolin_resource.demo_planning.subdomain == "demo-planning"
      && pangolin_resource.demo_planning_kc.domain_id == "dom-dev" && pangolin_resource.demo_planning_kc.subdomain == "demo-planning-kc"
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
    condition = alltrue([
      for r in [
        pangolin_resource.bbox, pangolin_resource.betisier, pangolin_resource.traefik_dashboard,
        pangolin_resource.dawarich, pangolin_resource.demo_planning, pangolin_resource.demo_planning_kc,
        pangolin_resource.echo, pangolin_resource.flip_planning, pangolin_resource.gramps,
        pangolin_resource.immich, pangolin_resource.immich_swipe, pangolin_resource.meerkat_crm,
        pangolin_resource.monica, pangolin_resource.nas, pangolin_resource.nextcloud,
        pangolin_resource.paperless, pangolin_resource.proxmox, pangolin_resource.rss,
        pangolin_resource.scanopy, pangolin_resource.searxng, pangolin_resource.trek,
        pangolin_resource.wiki,
      ] :
      r.maintenance_mode_enabled == true
      && r.maintenance_mode_type == "automatic"
      && r.maintenance_title == pangolin_resource.flip_planning.maintenance_title
    ])
    error_message = "Chaque ressource doit servir la page de maintenance en mode automatic, avec le même titre."
  }

  assert {
    condition = alltrue([
      for m in [
        uptimekuma_monitor_http_keyword.betisier,
        uptimekuma_monitor_http_keyword.dawarich,
        uptimekuma_monitor_http_keyword.demo_planning,
        uptimekuma_monitor_http_keyword.echo,
        uptimekuma_monitor_http_keyword.flip_planning,
        uptimekuma_monitor_http_keyword.gramps,
        uptimekuma_monitor_http_keyword.immich,
        uptimekuma_monitor_http_keyword.immich_swipe,
        uptimekuma_monitor_http_keyword.meerkat_crm,
        uptimekuma_monitor_http_keyword.monica,
        uptimekuma_monitor_http_keyword.nas,
        uptimekuma_monitor_http_keyword.nextcloud,
        uptimekuma_monitor_http_keyword.paperless,
        uptimekuma_monitor_http_keyword.proxmox,
        uptimekuma_monitor_http_keyword.rss,
        uptimekuma_monitor_http_keyword.scanopy,
        uptimekuma_monitor_http_keyword.searxng,
        uptimekuma_monitor_http_keyword.trek,
        uptimekuma_monitor_http_keyword.wiki,
      ] :
      m.invert_keyword == true
      && m.keyword == pangolin_resource.flip_planning.maintenance_title
    ])
    error_message = "Chaque healthcheck doit chercher le titre de la page de maintenance en mot-clé inversé : sinon la page (HTTP 200) passe pour un service sain."
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

  assert {
    condition = alltrue([
      for r in [
        pangolin_resource.bbox, pangolin_resource.betisier, pangolin_resource.traefik_dashboard,
        pangolin_resource.dawarich, pangolin_resource.demo_planning, pangolin_resource.demo_planning_kc,
        pangolin_resource.echo, pangolin_resource.flip_planning, pangolin_resource.gramps,
        pangolin_resource.immich, pangolin_resource.immich_swipe, pangolin_resource.meerkat_crm,
        pangolin_resource.monica, pangolin_resource.nas, pangolin_resource.nextcloud,
        pangolin_resource.paperless, pangolin_resource.proxmox, pangolin_resource.rss,
        pangolin_resource.scanopy, pangolin_resource.searxng, pangolin_resource.trek,
        pangolin_resource.wiki,
      ] :
      try(
        pangolin_resource_rule.block_country[r.name].resource_id == r.id
        && pangolin_resource_rule.allow_countries["${r.name}-FR"].resource_id == r.id
        && pangolin_resource_rule.allow_countries["${r.name}-DE"].resource_id == r.id,
        false
      )
    ])
    error_message = "Une entrée de local.managed_resources ne porte pas le nom exact de la ressource vers laquelle elle pointe."
  }

  # Garde-fou du test lui-même : sans identifiants distincts, l'égalité
  # ci-dessus serait vraie par construction.
  assert {
    condition     = length(distinct([for rule in pangolin_resource_rule.block_country : rule.resource_id])) == 23
    error_message = "Les identifiants simulés des ressources doivent être distincts pour que ce run prouve quelque chose."
  }

  assert {
    condition = (
      pangolin_resource_rule.flip_planning_mcp.resource_id == pangolin_resource.flip_planning.id
      && pangolin_resource_rule.demo_planning_mcp.resource_id == pangolin_resource.demo_planning.id
      && pangolin_resource_rule.demo_planning_kc_keycloak.resource_id == pangolin_resource.demo_planning_kc.id
      && pangolin_resource_rule.immich_home_ip.resource_id == pangolin_resource.immich.id
      && pangolin_resource_rule.dawarich_home_ip.resource_id == pangolin_resource.dawarich.id
      && pangolin_resource_rule.trek_home_ip.resource_id == pangolin_resource.trek.id
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
      output.uptime_backup_searxng_url,
      output.uptime_backup_paperless_url,
      output.uptime_backup_flip_planning_url,
      output.uptime_backup_demo_planning_url,
      output.uptime_backup_immich_url,
      output.uptime_backup_pangolin_url,
    ])) == 17
    error_message = "Deux sorties lues par Ansible pointent sur le même moniteur push."
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
      pangolin_resource_access_token.flip_planning.resource_id == pangolin_resource.flip_planning.id
      && pangolin_resource_access_token.demo_planning.resource_id == pangolin_resource.demo_planning.id
      && pangolin_resource_access_token.flip_planning.token != pangolin_resource_access_token.demo_planning.token
    )
    error_message = "Chaque environnement doit avoir son propre jeton d'accès, rattaché à sa propre ressource."
  }

  assert {
    condition = (
      jsondecode(uptimekuma_monitor_http_keyword.flip_planning.headers)["P-Access-Token-Id"] == "tok-flip-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.flip_planning.headers)["P-Access-Token"] == "jeton-flip-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.demo_planning.headers)["P-Access-Token-Id"] == "tok-demo-planning"
      && jsondecode(uptimekuma_monitor_http_keyword.demo_planning.headers)["P-Access-Token"] == "jeton-demo-planning"
    )
    error_message = "Chaque healthcheck doit s'authentifier avec le jeton de SON environnement."
  }

  assert {
    condition = (
      uptimekuma_monitor_http_keyword.flip_planning.url == "https://flip-planning.sylvain.cloud"
      && uptimekuma_monitor_http_keyword.demo_planning.url == "https://demo-planning.sylvain.dev"
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
      uptimekuma_monitor_push.backup_flip_planning.name == "Backup Flip Planning"
      && uptimekuma_monitor_push.backup_demo_planning.name == "Backup Demo Planning"
    )
    error_message = "Chaque environnement doit avoir son propre moniteur de sauvegarde."
  }

  assert {
    condition = (
      pangolin_resource_role.flip_planning.resource_id == pangolin_resource.flip_planning.id
      && pangolin_resource_role.demo_planning.resource_id == pangolin_resource.demo_planning.id
      && pangolin_resource_role.demo_planning_kc.resource_id == pangolin_resource.demo_planning_kc.id
    )
    error_message = "Chaque ressource de Flip Planning porte sa propre liaison de rôle."
  }

  assert {
    condition = alltrue([
      for r in [pangolin_resource.flip_planning, pangolin_resource.demo_planning, pangolin_resource.demo_planning_kc] :
      r.sso == true && r.apply_rules == true && r.enabled == true
    ])
    error_message = "Les trois environnements de Flip Planning restent derrière le SSO, avec les règles appliquées."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.flip_planning,
        pangolin_target.flip_planning_pgadmin,
        pangolin_target.flip_planning_mailpit,
        pangolin_target.flip_planning_assets,
      ] : t.resource_id == pangolin_resource.flip_planning.id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles de production doivent appartenir à la ressource Flip Planning, sur le site flip."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.demo_planning,
        pangolin_target.demo_planning_pgadmin,
        pangolin_target.demo_planning_mailpit,
        pangolin_target.demo_planning_assets,
      ] : t.resource_id == pangolin_resource.demo_planning.id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles de démo doivent appartenir à la ressource Demo Planning, sur le site flip."
  }

  assert {
    condition = alltrue([
      for t in [
        pangolin_target.demo_planning_kc,
        pangolin_target.demo_planning_kc_pgadmin,
        pangolin_target.demo_planning_kc_mailpit,
        pangolin_target.demo_planning_kc_assets,
        pangolin_target.demo_planning_kc_keycloak,
      ] : t.resource_id == pangolin_resource.demo_planning_kc.id && t.site_id == pangolin_site.flip.id
    ])
    error_message = "Les cibles du banc KC doivent appartenir à la ressource Demo Planning KC, sur le site flip."
  }

  assert {
    condition = (
      toset([
        pangolin_target.flip_planning.ip,
        pangolin_target.flip_planning_pgadmin.ip,
        pangolin_target.flip_planning_mailpit.ip,
        pangolin_target.flip_planning_assets.ip,
        ]) == toset([
        "flip-planning", "flip-planning-pgadmin", "flip-planning-mailpit", "flip-planning-assets",
      ])
      && toset([
        pangolin_target.demo_planning.ip,
        pangolin_target.demo_planning_pgadmin.ip,
        pangolin_target.demo_planning_mailpit.ip,
        pangolin_target.demo_planning_assets.ip,
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
# personne, comme gramps et scanopy en 503 pendant des heures).
run "monitors_are_filed_and_notify_by_email" {
  command = apply

  assert {
    condition = alltrue([
      for m in [
        uptimekuma_monitor_push.backup_betisier,
        uptimekuma_monitor_push.backup_dawarich,
        uptimekuma_monitor_push.backup_demo_planning,
        uptimekuma_monitor_push.backup_flip_planning,
        uptimekuma_monitor_push.backup_gramps,
        uptimekuma_monitor_push.backup_immich,
        uptimekuma_monitor_push.backup_meerkat_crm,
        uptimekuma_monitor_push.backup_monica,
        uptimekuma_monitor_push.backup_nextcloud,
        uptimekuma_monitor_push.backup_pangolin,
        uptimekuma_monitor_push.backup_paperless,
        uptimekuma_monitor_push.backup_rss,
        uptimekuma_monitor_push.backup_scanopy,
        uptimekuma_monitor_push.backup_searxng,
        uptimekuma_monitor_push.backup_trek,
        uptimekuma_monitor_push.backup_wiki,
      ] :
      m.parent == uptimekuma_monitor_group.backups.id
      && m.interval == 86400
      && m.active == true
      && contains(m.notification_ids, uptimekuma_notification_smtp.email.id)
    ])
    error_message = "Chaque moniteur de sauvegarde doit être dans le dossier Backup, quotidien, actif et notifié par e-mail."
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
      for m in [
        uptimekuma_monitor_http_keyword.betisier,
        uptimekuma_monitor_http_keyword.dawarich,
        uptimekuma_monitor_http_keyword.demo_planning,
        uptimekuma_monitor_http_keyword.echo,
        uptimekuma_monitor_http_keyword.flip_planning,
        uptimekuma_monitor_http_keyword.gramps,
        uptimekuma_monitor_http_keyword.immich,
        uptimekuma_monitor_http_keyword.immich_swipe,
        uptimekuma_monitor_http_keyword.meerkat_crm,
        uptimekuma_monitor_http_keyword.monica,
        uptimekuma_monitor_http_keyword.nas,
        uptimekuma_monitor_http_keyword.nextcloud,
        uptimekuma_monitor_http_keyword.paperless,
        uptimekuma_monitor_http_keyword.proxmox,
        uptimekuma_monitor_http_keyword.rss,
        uptimekuma_monitor_http_keyword.scanopy,
        uptimekuma_monitor_http_keyword.searxng,
        uptimekuma_monitor_http_keyword.trek,
        uptimekuma_monitor_http_keyword.wiki,
      ] :
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
