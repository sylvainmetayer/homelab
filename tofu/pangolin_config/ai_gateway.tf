# ---------------------------------------------------------------------------
# Passerelle IA de Pangolin (AI Gateway, Pangolin >= 1.22) : https://ia.sylvain.cloud
#
# Les applis du homelab appellent les modèles par cette ressource `inference`,
# chacune avec sa clé virtuelle et son budget, au lieu d'une clé Anthropic par
# appli. Phase d'essai : une seule clé, « essai » ; les clés des applis
# (Papra, HealthLog, MCP) viendront après l'essai et l'ADR 0031.
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

  name                  = "anthropic"
  type                  = "anthropic"
  upstream_url          = "https://api.anthropic.com"
  api_key               = local.ai_anthropic_api_key
  auth_type             = "x-api-key"
  capabilities          = ["anthropic_messages", "v1_models"]
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

# Une ressource publique comme les autres : dans local.managed_resources
# (rules.tf), donc filtrée FR/DE et auditée. L'authentification ne se coupe pas
# (clé virtuelle ou SSO) ; sans liaison de rôle, seuls les administrateurs de
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
}

output "ai_gateway_url" {
  description = "URL de la passerelle IA (vide si local.ai_gateway_enabled est faux)"
  value       = try("https://${pangolin_resource.ai_gateway["ia"].full_domain}", "")
}

output "ai_gateway_keys" {
  description = "Clés virtuelles de la passerelle IA, par appli (tofu output -json ai_gateway_keys)"
  value       = { for k, v in pangolin_virtual_api_key.ai : k => v.secret }
  sensitive   = true
}
