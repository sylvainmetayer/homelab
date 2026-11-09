# ---------------------------------------------------------------------------
# Passerelle IA de Pangolin (AI Gateway, Pangolin >= 1.22) : https://ia.sylvain.cloud
#
# Les applis du homelab appellent les modèles par cette ressource `inference`,
# chacune avec sa clé virtuelle et son budget, au lieu d'une clé Anthropic par
# appli. Phase d'essai : la clé « essai » et celle d'Immich Power Tools ; les
# autres (Papra, HealthLog, MCP) viendront après l'essai et l'ADR 0031.
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

  # Liste d'autorisation du fournisseur : seuls ces modèles passent, et seuls
  # eux sont comptés en dollars par les budgets (catalogue de Pangolin).
  ai_models = {
    haiku  = { key = "claude-haiku-5-5", name = "Claude Haiku 5.5" }
    sonnet = { key = "claude-sonnet-5-5", name = "Claude Sonnet 5.5" }
    opus   = { key = "claude-opus-5-5", name = "Claude Opus 5.5" }
  }

  # Une clé virtuelle par appli, chacune plafonnée chaque mois (en dollars).
  ai_keys = {
    essai = {
      description = "Essai de la passerelle (appel, puis refus au-delà du budget)"
      budget_usd  = 1
    }
    # Recherche « Find » (analyse de la requête), format OpenAI, Haiku. Clé
    # lue par ansible/pi.yml (terraform_outputs.ai_gateway_keys) pour le rôle
    # immich ; une clé remplacée (-replace) se redéploie par pi.yml.
    immich_power_tools = {
      description = "Immich Power Tools : recherche Find"
      budget_usd  = 5
    }
  }

  # Plafond de toute l'organisation, toutes clés confondues.
  ai_budget_total_usd = 20
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

resource "pangolin_ai_budget" "total" {
  for_each = local.ai_gateway

  amount      = local.ai_budget_total_usd
  unit        = "usd"
  period      = "monthly"
  enforcement = "hard"
  enabled     = true
}

resource "pangolin_ai_budget" "key" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_keys : {}

  virtual_api_key_id = pangolin_virtual_api_key.ai[each.key].id
  amount             = each.value.budget_usd
  unit               = "usd"
  period             = "monthly"
  enforcement        = "hard"
  enabled            = true

  # Pangolin supprime le budget avec sa clé : une clé remplacée (-replace après
  # une fuite) laissait le provider tenter une mise à jour d'un budget disparu.
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
