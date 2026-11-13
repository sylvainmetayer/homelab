# ---------------------------------------------------------------------------
# Passerelle IA de Pangolin (AI Gateway, Pangolin >= 1.22) : https://ia.sylvain.cloud
#
# Les applis du homelab appellent les modèles par cette ressource `inference`,
# chacune avec sa clé virtuelle, au lieu d'une clé Anthropic par appli. Phase
# d'essai : la clé « essai » et celles des applis (local.ai_keys) ;
# MCP viendra après l'essai et l'ADR 0032.
#
# Allumée par local.ai_gateway_enabled, jamais par la seule présence de sa
# clé : une clé SOPS perdue (fusion ratée dans le sous-module) détruirait sans
# un mot la passerelle et les clés virtuelles des applis, irrécupérables. Le
# plan échoue donc si l'interrupteur est vrai et que la clé
# `pangolin_ai_anthropic_api_key` (secrets/secrets.sops.yaml) manque : une clé
# de l'API Anthropic dans un workspace dédié, avec sa propre limite de dépense
# chez Anthropic (lue ici, pas dans secrets.tf, avec cette passerelle).
#
# Pas de budget de passerelle pour l'instant : le seul plafond est la limite de
# dépense du workspace Anthropic. Les budgets (pangolin_ai_budget, mensuels) sont
# à remettre quand une version de Pangolin contiendra fosrl/pangolin#4077 (les
# fenêtres de période comparent des secondes à des millisecondes : un budget
# périodique ne bloque jamais). Blocs retirés : voir l'historique git (PR « retirer
# les budgets de la passerelle IA »).
#
# Journal des appels (« AI Gateway Session Log Retention », réglage de
# l'organisation : log_retention_days_ai_sessions dans org.tf) : 90 jours
# depuis le 12/11/2026 (décision de Sylvain). Il garde les prompts et les
# réponses en entier, sans masquage (README) ; 0 l'éteint.
#
# Tous les attributs optionnels+calculés sont déclarés (AGENTS.md) : non
# déclarés, un changement fait dans l'interface passerait inaperçu au plan.
# ---------------------------------------------------------------------------

locals {
  ai_gateway_enabled = true
  ai_gateway         = local.ai_gateway_enabled ? toset(["ia"]) : toset([])

  # Liste d'autorisation du fournisseur : seuls ces modèles passent.
  ai_models = {
    haiku  = { key = "claude-haiku-5-5", name = "Claude Haiku 5.5" }
    sonnet = { key = "claude-sonnet-5-5", name = "Claude Sonnet 5.5" }
    opus   = { key = "claude-opus-5-5", name = "Claude Opus 5.5" }
  }

  # Une clé virtuelle par appli.
  ai_keys = {
    essai = {
      description = "Essai de la passerelle (appel, puis refus au-delà du budget)"
    }
    # Recherche « Find » (analyse de la requête), format OpenAI, Haiku. Clé
    # lue par ansible/pi.yml (terraform_outputs.ai_gateway_keys) pour le rôle
    # immich ; une clé remplacée (-replace) se redéploie par pi.yml.
    immich_power_tools = {
      description = "Immich Power Tools : recherche Find"
    }
    # Tags et résumés des favoris, format OpenAI, Haiku (rôle karakeep,
    # docker.yml).
    karakeep = {
      description = "Karakeep : tags et résumés"
    }
    # Assistant de Nextcloud (appli integration_openai), format OpenAI, Haiku
    # (rôle nextcloud, docker.yml).
    nextcloud = {
      description = "Nextcloud Assistant"
    }
    # Coach et analyses, format OpenAI ; URL de base et clé saisies à la main
    # dans /settings/ai (README du rôle healthlog). Données de santé : journal
    # des appels éteint.
    healthlog = {
      description = "HealthLog : coach et analyses"
    }
    # papra-enrich.timer (rôle papra, docker.yml), format OpenAI, Haiku :
    # Montant, Fin de validité et tags. ~3 650 tokens par document, ~400 en
    # arriéré (mesure du 2026-11-10) : 5 M.
    papra = {
      description = "Papra : classement des documents"
    }
    # Chat du foyer (openwebui.sylvain.cloud), Haiku, Sonnet et Opus.
    openwebui = {
      description = "Open WebUI : chat du foyer"
    }
  }
}

resource "terraform_data" "ai_gateway_key" {
  input = local.ai_gateway_enabled

  lifecycle {
    precondition {
      condition     = !local.ai_gateway_enabled || nonsensitive(local.ai_anthropic_api_key != "")
      error_message = "Passerelle IA allumée (local.ai_gateway_enabled, ai_gateway.tf) sans la clé SOPS pangolin_ai_anthropic_api_key dans secrets/secrets.sops.yaml (ou son TF_VAR_ai_anthropic_api_key absent de mise.toml). La mettre (et son entrée dans secrets-rotation.yaml), ou passer l'interrupteur à false pour tout retirer."
    }
  }
}

resource "pangolin_ai_provider" "anthropic" {
  for_each = local.ai_gateway

  name         = "anthropic"
  type         = "anthropic"
  upstream_url = "https://api.anthropic.com"
  api_key      = local.ai_anthropic_api_key
  auth_type    = "x-api-key"
  # openai_chat : le point compatible OpenAI d'Anthropic (/v1/chat/completions),
  # pour les applis qui ne parlent qu'OpenAI (Immich Power Tools).
  capabilities          = ["anthropic_messages", "openai_chat", "v1_models"]
  routing_mode          = "url"
  enabled               = true
  skip_tls_verification = false
}

resource "pangolin_ai_model" "anthropic" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_models : {}

  provider_id = pangolin_ai_provider.anthropic["ia"].id
  model_key   = each.value.key
  name        = each.value.name
  list_type   = "allow"
  enabled     = true
}

# Hors de local.managed_resources : Pangolin refuse les règles (pays, chemins)
# sur une ressource `inference`, elle n'est donc pas filtrée FR/DE
# (local.unruled_resources, rules.tf). L'authentification ne se coupe pas (clé
# virtuelle ou SSO) ; sans liaison de rôle, seuls les administrateurs de
# l'organisation y obtiennent une clé d'identité par le navigateur.
resource "pangolin_resource" "ai_gateway" {
  for_each = local.ai_gateway

  name            = "Passerelle IA"
  mode            = "inference"
  subdomain       = each.key
  domain_id       = local.domain_ids["sylvain.cloud"]
  sso             = true
  skip_to_idp_id  = pangolin_idp.pocket_id.id
  apply_rules     = true
  ai_provider_ids = [pangolin_ai_provider.anthropic[each.key].id]

  # Mêmes épingles que pangolin_resource.website (resource_defaults.tf), sauf
  # `mode`.
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session
  resource_policy_id      = local.resource_pins.resource_policy_id

  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_virtual_api_key" "ai" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_keys : {}

  name          = "ia-${each.key}"
  description   = each.value.description
  all_resources = false
  resource_ids  = [pangolin_resource.ai_gateway["ia"].id]
}

output "ai_gateway_url" {
  description = "URL de la passerelle IA (vide si local.ai_gateway_enabled est faux)"
  value       = try("https://${pangolin_resource.ai_gateway["ia"].full_domain}", "")
}

output "ai_gateway_keys" {
  description = "Clés virtuelles de la passerelle IA, par appli, prêtes à l'emploi (tofu output -json ai_gateway_keys)"
  # Le provider ne rend que le secret ; la passerelle attend pangolin-key-<id>.<secret>.
  value     = { for k, v in pangolin_virtual_api_key.ai : k => "pangolin-key-${v.id}.${v.secret}" }
  sensitive = true
}

# Sonde de la passerelle : un GET sans clé, qui doit répondre 401 (constaté sur
# toutes les routes : Pangolin refuse l'appel avant tout appel amont). Elle voit
# la ressource, Traefik et la passerelle vivants, sans clé de sonde ni appel
# facturé ; une clé Anthropic révoquée ne se voit pas ici. Pas de mot-clé de
# maintenance : la page de maintenance répond 200, hors des codes acceptés, donc
# DOWN comme il faut.
resource "uptimekuma_monitor_http" "ai_gateway" {
  for_each = local.ai_gateway

  name = "Passerelle IA"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.ai_gateway[each.key].full_domain}/v1/models"
  interval        = local.http_probe.interval
  timeout         = 30
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  accepted_status_codes = ["401"]
  expiry_notification   = true
  tags                  = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}
