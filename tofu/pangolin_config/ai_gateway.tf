# ---------------------------------------------------------------------------
# Passerelle IA de Pangolin (AI Gateway, Pangolin >= 1.22) : https://ia.sylvain.cloud
#
# Les applis du homelab appellent les modèles par cette ressource `inference`,
# chacune avec sa clé virtuelle et son budget, au lieu d'une clé Anthropic par
# appli. Phase d'essai : la clé « essai » et celles des applis (local.ai_keys) ;
# MCP viendra après l'essai et l'ADR 0031.
#
# Allumée par local.ai_gateway_enabled, jamais par la seule présence de sa
# clé : une clé SOPS perdue (fusion ratée dans le sous-module) détruirait sans
# un mot la passerelle et les clés virtuelles des applis, irrécupérables. Le
# plan échoue donc si l'interrupteur est vrai et que la clé
# `pangolin_ai_anthropic_api_key` (secrets/secrets.sops.yaml) manque : une clé
# de l'API Anthropic dans un workspace dédié, avec sa propre limite de dépense
# chez Anthropic, en plus des budgets ci-dessous (lue ici, pas dans secrets.tf,
# avec cette passerelle).
#
# Journal des appels (« AI Gateway Session Log Retention », réglage de
# l'organisation, hors du provider) : laissé à 0 jour, soit éteint ; les
# statistiques d'usage par clé restent. Le rallumer quelques heures pour
# déboguer, puis le remettre à 0 : il garde les prompts et les réponses en
# entier, sans masquage (README).
#
# Tous les attributs optionnels+calculés sont déclarés (AGENTS.md) : non
# déclarés, un changement fait dans l'interface passerait inaperçu au plan.
# ---------------------------------------------------------------------------

locals {
  ai_gateway_enabled   = true
  ai_gateway           = local.ai_gateway_enabled ? toset(["ia"]) : toset([])
  ai_anthropic_api_key = try(data.sops_file.secrets.data["pangolin_ai_anthropic_api_key"], "")

  # Liste d'autorisation du fournisseur : seuls ces modèles passent (les
  # budgets en dollars ne comptent que ceux du catalogue de prix de Pangolin).
  ai_models = {
    haiku  = { key = "claude-haiku-5-5", name = "Claude Haiku 5.5" }
    sonnet = { key = "claude-sonnet-5-5", name = "Claude Sonnet 5.5" }
    opus   = { key = "claude-opus-5-5", name = "Claude Opus 5.5" }
  }

  # Une clé virtuelle par appli, deux budgets chacune : en tokens, bloquant
  # (hard, sur `lifetime` : voir pangolin_ai_budget.total_tokens), et en
  # dollars, mensuel, en suivi seul (soft). Les budgets en
  # dollars ne comptent que les modèles du catalogue de prix de Pangolin, où les
  # claude-*-5-5 manquaient le 2026-11-09 : la clé essai, plafonnée à 1 $, a
  # passé plusieurs dollars d'Opus sans un refus. Les tokens ne demandent aucun
  # prix ; tous modèles confondus (un token d'Opus en vaut cinq de Haiku).
  ai_keys = {
    essai = {
      description   = "Essai de la passerelle (appel, puis refus au-delà du budget)"
      budget_usd    = 1
      budget_tokens = 20000
    }
    # Recherche « Find » (analyse de la requête), format OpenAI, Haiku. Clé
    # lue par ansible/pi.yml (terraform_outputs.ai_gateway_keys) pour le rôle
    # immich ; une clé remplacée (-replace) se redéploie par pi.yml.
    immich_power_tools = {
      description   = "Immich Power Tools : recherche Find"
      budget_usd    = 5
      budget_tokens = 2000000
    }
    # Tags et résumés des favoris, format OpenAI, Haiku (rôle karakeep,
    # docker.yml).
    karakeep = {
      description   = "Karakeep : tags et résumés"
      budget_usd    = 5
      budget_tokens = 2000000
    }
    # Assistant de Nextcloud (appli integration_openai), format OpenAI, Haiku
    # (rôle nextcloud, docker.yml).
    nextcloud = {
      description   = "Nextcloud Assistant"
      budget_usd    = 5
      budget_tokens = 2000000
    }
    # Coach et analyses, format OpenAI ; URL de base et clé saisies à la main
    # dans /settings/ai (README du rôle healthlog). Données de santé : journal
    # des appels éteint.
    healthlog = {
      description   = "HealthLog : coach et analyses"
      budget_usd    = 5
      budget_tokens = 2000000
    }
    # Module IA de Papra (adaptateur openai-compatible), Haiku (rôle papra,
    # docker.yml).
    papra = {
      description   = "Papra : classement des documents"
      budget_usd    = 5
      budget_tokens = 2000000
    }
    # Chat du foyer (openwebui.sylvain.cloud), Haiku, Sonnet et Opus.
    openwebui = {
      description   = "Open WebUI : chat du foyer"
      budget_usd    = 10
      budget_tokens = 5000000
    }
  }

  # Plafonds de toute l'organisation, toutes clés confondues.
  ai_budget_total_usd    = 30
  ai_budget_total_tokens = 20000000
}

resource "terraform_data" "ai_gateway_key" {
  input = local.ai_gateway_enabled

  lifecycle {
    precondition {
      condition     = !local.ai_gateway_enabled || nonsensitive(local.ai_anthropic_api_key != "")
      error_message = "Passerelle IA allumée (local.ai_gateway_enabled, ai_gateway.tf) sans la clé SOPS pangolin_ai_anthropic_api_key dans secrets/secrets.sops.yaml. L'ajouter (et son entrée dans secrets-rotation.yaml), ou passer l'interrupteur à false pour tout retirer."
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

# En dollars : suivi seul (soft), voir local.ai_keys.
resource "pangolin_ai_budget" "total" {
  for_each = local.ai_gateway

  amount      = local.ai_budget_total_usd
  unit        = "usd"
  period      = "monthly"
  enforcement = "soft"
  enabled     = true
}

# Les budgets en tokens bloquants sont sur `lifetime`, pas `monthly` : en
# 1.26.0, l'usage est enregistré en secondes et comparé à une fenêtre en
# millisecondes (server/lib/aiBudgetEnforcement.ts), si bien que toute période
# compte 0 et ne bloque jamais ; seul `lifetime` (sans borne basse) marche
# (fosrl/pangolin#4077). Sans remise à zéro : relever les plafonds à la main
# s'ils bloquent, et revenir à `monthly` quand la correction sera publiée.
resource "pangolin_ai_budget" "total_tokens" {
  for_each = local.ai_gateway

  amount      = local.ai_budget_total_tokens
  unit        = "tokens"
  period      = "lifetime"
  enforcement = "hard"
  enabled     = true
}

resource "pangolin_ai_budget" "key" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_keys : {}

  virtual_api_key_id = pangolin_virtual_api_key.ai[each.key].id
  amount             = each.value.budget_usd
  unit               = "usd"
  period             = "monthly"
  enforcement        = "soft"
  enabled            = true

  # Pangolin supprime le budget avec sa clé : une clé remplacée (-replace après
  # une fuite) laissait le provider tenter une mise à jour d'un budget disparu.
  lifecycle {
    replace_triggered_by = [pangolin_virtual_api_key.ai[each.key].id]
  }
}

resource "pangolin_ai_budget" "key_tokens" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_keys : {}

  virtual_api_key_id = pangolin_virtual_api_key.ai[each.key].id
  amount             = each.value.budget_tokens
  unit               = "tokens"
  period             = "lifetime"
  enforcement        = "hard"
  enabled            = true

  lifecycle {
    replace_triggered_by = [pangolin_virtual_api_key.ai[each.key].id]
  }
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
