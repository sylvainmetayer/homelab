# Les secrets de ce module arrivent par des variables d'entrée, alimentées par
# l'environnement : mise.toml exporte chaque TF_VAR_<nom> depuis la clé de
# secrets/secrets.sops.yaml qu'il a déjà chargée. Plus de data "sops_file" :
# une data source est écrite en entier dans le state, et celui-ci reste en
# clair sur S3 (Ansible le lit), avec les 33 clés du fichier dedans (audit du
# 11/11, constat sc1). Une variable n'entre dans le state que si une ressource
# la stocke : c'est le cas des seules valeurs ci-dessous marquées « state ».
# Les autres ne servent qu'à configurer un provider, ce que le state ne garde pas.
#
# Toutes sensibles, comme l'était le data source : les plans masquent les mêmes
# valeurs. Une variable vide ferait un plan faux sans rien casser (PIN
# recréés...) : chaque variable obligatoire refuse la chaîne vide, ce qui
# attrape un mapping de mise.toml qui ne passerait plus.

# Passphrase DÉDIÉE du chiffrement du state de ce module (encryption.tf), la
# même valeur que `tofu_state_passphrase` de secrets/ansible.sops.yaml (lue par
# Ansible et la CI). Clé SOPS TF_VAR_pangolin_config_state_passphrase de
# secrets/secrets.sops.yaml, que mise exporte telle quelle.
variable "pangolin_config_state_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state de ce module (clé SOPS TF_VAR_pangolin_config_state_passphrase)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pangolin_config_state_passphrase) != ""
    error_message = "TF_VAR_pangolin_config_state_passphrase est vide : lancer tofu par `mise exec --` (clé de secrets/secrets.sops.yaml)."
  }
}

variable "pangolin_org_id" {
  description = "Identifiant de l'organisation Pangolin (clé SOPS pangolin_org_id)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pangolin_org_id) != ""
    error_message = "TF_VAR_pangolin_org_id est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "pangolin_url" {
  description = "URL de l'API Pangolin (clé SOPS pangolin_url)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pangolin_url) != ""
    error_message = "TF_VAR_pangolin_url est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# State : les data "http" de rules.tf, access_inventory.tf et binding_inventory.tf la portent dans
# leurs en-têtes, que leur state garde.
variable "pangolin_api_key" {
  description = "Clé d'API de l'organisation Pangolin (clé SOPS pangolin_api_key)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pangolin_api_key) != ""
    error_message = "TF_VAR_pangolin_api_key est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# Clé « root » du serveur Pangolin, pour le fournisseur d'identité seulement
# (pocket_id.tf) : configuration du provider, pas dans le state.
variable "pangolin_root_api_key" {
  description = "Clé root de Pangolin (clé SOPS pangolin_root_api_key)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pangolin_root_api_key) != ""
    error_message = "TF_VAR_pangolin_root_api_key est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# Bot et salon de la notification Telegram (notifications.tf). State.
variable "telegram_bot_token" {
  description = "Jeton du bot Telegram (clé SOPS uptimekuma_telegram_bot_token)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.telegram_bot_token) != ""
    error_message = "TF_VAR_telegram_bot_token est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "telegram_chat_id" {
  description = "Salon Telegram des notifications (clé SOPS uptimekuma_telegram_chat_id)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.telegram_chat_id) != ""
    error_message = "TF_VAR_telegram_chat_id est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# State : l'adresse entre dans les URL des sorties de push.
variable "uptimekuma_endpoint" {
  description = "URL de l'instance Uptime Kuma (clé SOPS UPTIMEKUMA_ENDPOINT)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.uptimekuma_endpoint) != ""
    error_message = "TF_VAR_uptimekuma_endpoint est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "uptimekuma_username" {
  description = "Compte Uptime Kuma (clé SOPS UPTIMEKUMA_USERNAME)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.uptimekuma_username) != ""
    error_message = "TF_VAR_uptimekuma_username est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "uptimekuma_password" {
  description = "Mot de passe du compte Uptime Kuma (clé SOPS UPTIMEKUMA_PASSWORD)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.uptimekuma_password) != ""
    error_message = "TF_VAR_uptimekuma_password est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# State : valeurs de règles et de codes d'accès des ressources Pangolin.
variable "home_ip" {
  description = "IP publique du domicile (clé SOPS home_ip)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.home_ip) != ""
    error_message = "TF_VAR_home_ip est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "immich_pin" {
  description = "Code PIN de la ressource Immich (clé SOPS immich_pin)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.immich_pin) != ""
    error_message = "TF_VAR_immich_pin est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "flip_planning_pin" {
  description = "Code PIN de la ressource Flip Planning (clé SOPS flip_planning_pin)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.flip_planning_pin) != ""
    error_message = "TF_VAR_flip_planning_pin est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

variable "neonova_pin" {
  description = "Code PIN de la ressource Neonova (clé SOPS neonova_pin)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.neonova_pin) != ""
    error_message = "TF_VAR_neonova_pin est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# Jeton en écriture seule du producteur uptime-kuma de ntfy (website_ntfy.tf). State.
variable "ntfy_uptime_kuma_token" {
  description = "Jeton ntfy du producteur Uptime Kuma (clé SOPS ntfy_uptime_kuma_token)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.ntfy_uptime_kuma_token) != ""
    error_message = "TF_VAR_ntfy_uptime_kuma_token est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# STATIC_API_KEY de Pocket ID (pocket_id.tf, provider "pocketid") : configuration
# du provider, pas dans le state.
variable "pocket_id_api_token" {
  description = "STATIC_API_KEY de Pocket ID (clé SOPS pocket_id_static_api_key)."
  type        = string
  sensitive   = true
  validation {
    condition     = nonsensitive(var.pocket_id_api_token) != ""
    error_message = "TF_VAR_pocket_id_api_token est vide : lancer tofu par `mise exec --` (mise.toml, section TF_VAR)."
  }
}

# Clé Anthropic de la passerelle IA (ai_gateway.tf), facultative : vide, la
# précondition de terraform_data.ai_gateway_key fait échouer le plan tant que
# la passerelle est allumée. State.
variable "ai_anthropic_api_key" {
  description = "Clé API Anthropic de la passerelle IA (clé SOPS pangolin_ai_anthropic_api_key)."
  type        = string
  sensitive   = true
  default     = ""
}

# Adresse privée de flip (tofu/pangolin, variable flip_server), pour flip.internal
# (private_resources.tf). Elle était lue par terraform_remote_state, qui rangeait
# dans ce state toutes les sorties de tofu/pangolin, dont le mot de passe de la
# Storage Box. Une adresse du réseau privé n'est pas un secret : valeur en dur,
# qu'un test tient égale au défaut de tofu/pangolin.
variable "flip_private_ip" {
  description = "IP privée du serveur Flip Planning (défaut de flip_server.private_ip dans tofu/pangolin/variables.tf)."
  type        = string
  default     = "10.0.1.10"
}

locals {
  pangolin_org_id = var.pangolin_org_id
  pangolin_url    = var.pangolin_url
  # Les clés d'API de Pangolin : l'organisation (data "http" des audits) et la
  # clé root (fournisseur d'identité seulement).
  pangolin_api_key      = var.pangolin_api_key
  pangolin_root_api_key = var.pangolin_root_api_key

  telegram_bot_token = var.telegram_bot_token
  telegram_chat_id   = var.telegram_chat_id

  uptimekuma_endpoint = var.uptimekuma_endpoint
  uptimekuma_username = var.uptimekuma_username
  uptimekuma_password = var.uptimekuma_password
  home_ip             = var.home_ip
  immich_pin          = var.immich_pin
  neonova_pin         = var.neonova_pin
  flip_planning_pin   = var.flip_planning_pin

  ntfy_uptime_kuma_token = var.ntfy_uptime_kuma_token
  pocket_id_api_token    = var.pocket_id_api_token
  ai_anthropic_api_key   = var.ai_anthropic_api_key
}
