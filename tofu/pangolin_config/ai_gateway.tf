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
# Budgets (pangolin_ai_budget), deux par clé et deux pour l'organisation, tous
# `monthly` : en tokens, bloquants (hard) ; en dollars, en suivi seul (soft).
# `monthly` est une fenêtre GLISSANTE de 30 jours (Pangolin 1.27,
# server/lib/aiBudgetEnforcement.ts), pas le mois civil. Depuis 1.27.0 Pangolin
# compte aussi le coût des claude-*-5-5 ; les dollars restent en suivi par choix
# (Sylvain, 2026-11-22). Historique : retirés le 2026-11-13, un budget
# périodique ne bloquait jamais en 1.26 (fosrl/pangolin#4077).
#
# Journal des appels (« AI Gateway Session Log Retention », réglage de
# l'organisation : log_retention_days_ai_sessions dans org.tf) : 90 jours
# depuis le 12/11/2026 (décision de Sylvain). Il garde les prompts et les
# réponses en entier, sans masquage (README) ; 0 l'éteint.
#
# Second fournisseur, OpenRouter (essais, 2026-11-24) : une clé pour des
# centaines de modèles. Pangolin route par nom de modèle : `claude-*` reste chez
# Anthropic (fournisseur natif prioritaire), `mistralai/…`, `openai/…`,
# `google/…` ou `…:free` part chez OpenRouter (local.ai_openrouter_models).
# Toute clé virtuelle peut demander ces modèles : les applis restent sur les
# leurs, réglés à la main ; les modèles `:free` gardent souvent les prompts,
# jamais pour HealthLog, Papra ni le chat du foyer. Le vrai plafond en dollars
# est la limite de crédit du compte OpenRouter. Interrupteur et précondition
# comme pour Anthropic (local.ai_openrouter_enabled, clé SOPS
# `pangolin_ai_openrouter_api_key`).
#
# Tous les attributs optionnels+calculés sont déclarés (AGENTS.md), budgets
# compris (enabled, enforcement, period) : non déclarés, un changement fait dans
# l'interface passerait inaperçu au plan.
# ---------------------------------------------------------------------------

locals {
  ai_gateway_enabled = true
  ai_gateway         = local.ai_gateway_enabled ? toset(["ia"]) : toset([])

  ai_openrouter_enabled = true
  ai_openrouter         = local.ai_openrouter_enabled ? local.ai_gateway : toset([])

  # Liste d'autorisation du fournisseur : seuls ces modèles passent.
  ai_models = {
    haiku  = { key = "claude-haiku-5-5", name = "Claude Haiku 5.5" }
    sonnet = { key = "claude-sonnet-5-5", name = "Claude Sonnet 5.5" }
    opus   = { key = "claude-opus-5-5", name = "Claude Opus 5.5" }
  }

  # Liste d'autorisation d'OpenRouter, en jokers (* et ?, Pangolin
  # server/lib/aiModelKeyMatch.ts) : pas de `anthropic/*`, Claude passe en
  # direct. `openai/*` inclut des modèles très chers : la limite de crédit du
  # compte OpenRouter est le garde-fou.
  ai_openrouter_models = {
    mistral = { key = "mistralai/*", name = "Mistral (OpenRouter)" }
    openai  = { key = "openai/*", name = "OpenAI (OpenRouter)" }
    google  = { key = "google/*", name = "Google (OpenRouter)" }
    free    = { key = "*:free", name = "Modèles gratuits (OpenRouter)" }
  }

  # Une clé virtuelle par appli : budget_tokens (bloquant) et budget_usd (suivi
  # seul), sur 30 jours glissants ; valeurs de Sylvain, 2026-11-22. `essai` a
  # déjà 154 k tokens dans la fenêtre : bloquée dès l'apply, exprès, elle sert à
  # vérifier le refus.
  ai_keys = {
    essai = {
      description   = "Essai de la passerelle (appel, puis refus au-delà du budget)"
      budget_tokens = 20000
      budget_usd    = 1
    }
    # Recherche « Find » (analyse de la requête), format OpenAI, Haiku. Clé
    # lue par ansible/pi.yml (terraform_outputs.ai_gateway_keys) pour le rôle
    # immich ; une clé remplacée (-replace) se redéploie par pi.yml.
    immich_power_tools = {
      description   = "Immich Power Tools : recherche Find"
      budget_tokens = 500000
      budget_usd    = 1
    }
    # Tags et résumés des favoris, format OpenAI, Haiku (rôle karakeep,
    # docker.yml). 40 M seulement parce que le rattrapage du 9-10/11 (29,7 M
    # tokens) reste dans la fenêtre jusque vers le 10/12 : la ramener à
    # 5 000 000 après le 2026-12-11 (usage courant : ~40 k tokens en 12 jours).
    karakeep = {
      description   = "Karakeep : tags et résumés"
      budget_tokens = 40000000
      budget_usd    = 5
    }
    # Assistant de Nextcloud (appli integration_openai), format OpenAI, Haiku
    # (rôle nextcloud, docker.yml).
    nextcloud = {
      description   = "Nextcloud Assistant"
      budget_tokens = 500000
      budget_usd    = 1
    }
    # Coach et analyses, format OpenAI ; URL de base et clé saisies à la main
    # dans /settings/ai (README du rôle healthlog). Données de santé : journal
    # des appels éteint.
    healthlog = {
      description   = "HealthLog : coach et analyses"
      budget_tokens = 1000000
      budget_usd    = 2
    }
    # papra-enrich.timer (rôle papra, docker.yml), format OpenAI, Haiku :
    # Montant, Fin de validité et tags. ~3 650 tokens par document, ~400 en
    # arriéré (mesure du 2026-11-10).
    papra = {
      description   = "Papra : classement des documents"
      budget_tokens = 2000000
      budget_usd    = 2
    }
    # Chat du foyer (openwebui.sylvain.cloud), Haiku, Sonnet et Opus.
    openwebui = {
      description   = "Open WebUI : chat du foyer"
      budget_tokens = 2000000
      budget_usd    = 10
    }
    # Assistant d'écriture (texte alternatif des images, raccourcir un post),
    # format OpenAI (rôle openpost, flip.yml). Modèle `openai/gpt-4.1-mini`
    # par OpenRouter depuis le 2026-11-24 : Anthropic et Gemini refusent les
    # schémas JSON de la génération de posts (README du rôle openpost). Couper OpenRouter
    # (local.ai_openrouter_enabled) éteint donc l'IA d'OpenPost.
    openpost = {
      description   = "OpenPost : assistant d'écriture"
      budget_tokens = 1000000
      budget_usd    = 2
    }
    # Essais des modèles d'OpenRouter (comparaison avec Haiku, modèles
    # gratuits). Dollars approximatifs : Pangolin estime le prix d'un modèle
    # OpenRouter par son catalogue, et ne connaît pas les `:free`.
    openrouter = {
      description   = "Essais des modèles d'OpenRouter"
      budget_tokens = 2000000
      budget_usd    = 5
    }
  }

  # Plafonds de toute l'organisation, toutes clés confondues (30 jours glissants).
  ai_budget_total_tokens = 50000000
  ai_budget_total_usd    = 30
}

resource "terraform_data" "ai_gateway_key" {
  input = local.ai_gateway_enabled

  lifecycle {
    precondition {
      condition     = !local.ai_gateway_enabled || nonsensitive(local.ai_anthropic_api_key != "")
      error_message = "Passerelle IA allumée (local.ai_gateway_enabled, ai_gateway.tf) sans la clé SOPS pangolin_ai_anthropic_api_key dans secrets/secrets.sops.yaml (ou son TF_VAR_ai_anthropic_api_key absent de mise.toml). La mettre (et son entrée dans secrets-rotation.yaml), ou passer l'interrupteur à false pour tout retirer."
    }
    precondition {
      condition     = length(local.ai_openrouter) == 0 || nonsensitive(local.ai_openrouter_api_key != "")
      error_message = "OpenRouter allumé (local.ai_openrouter_enabled, ai_gateway.tf) sans la clé SOPS pangolin_ai_openrouter_api_key dans secrets/secrets.sops.yaml (ou son TF_VAR_ai_openrouter_api_key absent de mise.toml). La mettre (et son entrée dans secrets-rotation.yaml), ou passer local.ai_openrouter_enabled à false."
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

resource "pangolin_ai_provider" "openrouter" {
  for_each = local.ai_openrouter

  name         = "openrouter"
  type         = "openRouter"
  upstream_url = "https://openrouter.ai/api/v1"
  api_key      = local.ai_openrouter_api_key
  auth_type    = "bearer"
  # Les valeurs par défaut du type dans Pangolin (src/lib/aiProviderDefaults.ts).
  capabilities          = ["openai_chat"]
  routing_mode          = "url"
  enabled               = true
  skip_tls_verification = false
}

resource "pangolin_ai_model" "openrouter" {
  for_each = length(local.ai_openrouter) > 0 ? local.ai_openrouter_models : {}

  provider_id = pangolin_ai_provider.openrouter["ia"].id
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
  ai_provider_ids = concat([pangolin_ai_provider.anthropic[each.key].id], [for p in pangolin_ai_provider.openrouter : p.id])

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

# Les budgets en dollars suivent seulement (soft), voir local.ai_keys.
resource "pangolin_ai_budget" "total" {
  for_each = local.ai_gateway

  amount      = local.ai_budget_total_usd
  unit        = "usd"
  period      = "monthly"
  enforcement = "soft"
  enabled     = true
}

resource "pangolin_ai_budget" "total_tokens" {
  for_each = local.ai_gateway

  amount      = local.ai_budget_total_tokens
  unit        = "tokens"
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
  enforcement        = "soft"
  enabled            = true

  # Pangolin supprime le budget avec sa clé : une clé remplacée (-replace après
  # une fuite) laissait le provider tenter une mise à jour d'un budget disparu.
  lifecycle {
    replace_triggered_by = [pangolin_virtual_api_key.ai[each.key].id]
  }
}

# Rappel daté du plafond provisoire de Karakeep (local.ai_keys) : après le
# 2026-12-11, son rattrapage du 9-10/11 est sorti de la fenêtre de 30 jours ;
# ce check avertit au plan tant que le plafond n'est pas redescendu à 5 M.
check "karakeep_ai_budget_stale" {
  assert {
    condition = (
      timecmp(plantimestamp(), "2026-12-11T00:00:00Z") < 0
      || local.ai_keys.karakeep.budget_tokens <= 5000000
    )
    error_message = "Le plafond de tokens de la clé karakeep (local.ai_keys, ai_gateway.tf) est encore à ${local.ai_keys.karakeep.budget_tokens} : son rattrapage est sorti de la fenêtre, le ramener à 5000000."
  }
}

resource "pangolin_ai_budget" "key_tokens" {
  for_each = length(local.ai_gateway) > 0 ? local.ai_keys : {}

  virtual_api_key_id = pangolin_virtual_api_key.ai[each.key].id
  amount             = each.value.budget_tokens
  unit               = "tokens"
  period             = "monthly"
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
