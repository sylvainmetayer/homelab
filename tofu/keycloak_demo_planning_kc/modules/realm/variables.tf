variable "keycloak_url" {
  description = <<-EOT
    URL PUBLIQUE de l'instance Keycloak, celle que les navigateurs verront.

    C'est elle qui signe l'émetteur des jetons, et l'application refuse un
    jeton dont l'émetteur ne correspond pas à l'autorité qu'elle a découverte.
  EOT
  type        = string
}

variable "admin_username" {
  description = <<-EOT
    Compte d'administration avec lequel Terraform se connecte au realm master.
    Null : le fournisseur lit KEYCLOAK_USER.
  EOT
  type        = string
  default     = null
}

variable "admin_password" {
  description = <<-EOT
    Mot de passe de ce compte. Null : le fournisseur lit KEYCLOAK_PASSWORD.
    Jamais dans terraform.tfvars : par l'environnement, ou passé par la
    configuration qui appelle ce dossier comme module, depuis son coffre.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "realm" {
  description = "Nom du realm, qui sert aussi d'identifiant interne. Doit correspondre à OIDC_PROVISIONING_REALM."
  type        = string
  default     = "planning"
}

variable "realm_display_name" {
  description = "Nom affiché du realm sur l'écran de connexion et dans les e-mails."
  type        = string
  default     = "Planning Équipes"
}

variable "login_theme" {
  description = <<-EOT
    Thème de la page de connexion. « planning » est celui de l'image du dépôt
    (ghcr.io/…/planning-equipes-keycloak) : connexion aux couleurs du produit,
    visuels du client montés dans brand/ — docs/keycloak.md § Le thème. Sur
    un Keycloak qui ne le porte pas, mettre « keycloak » : Keycloak
    retomberait sinon sur son thème en ne le disant que dans son journal.
  EOT
  type        = string
  default     = "planning"
}

variable "events_expiration_seconds" {
  description = "Durée de conservation des événements utilisateur et d'administration du realm, en secondes. 7 jours par défaut : des données personnelles, gardées le temps d'un diagnostic."
  type        = number
  default     = 604800
}

variable "account_theme" {
  description = "Thème de la console de compte (mot de passe, passkey, second facteur), même image et même règle que login_theme."
  type        = string
  default     = "planning"
}

variable "email_theme" {
  description = "Thème des e-mails du realm, même image et même règle que login_theme."
  type        = string
  default     = "planning"
}

variable "planning_public_url" {
  description = "URL publique de l'instance Planning Équipes, sans barre finale."
  type        = string

  validation {
    condition     = can(regex("^https://[^/*]+$", var.planning_public_url))
    error_message = "Une origine https sans chemin ni barre finale, ex. https://planning.exemple.org : elle sert à bâtir les URI de redirection, et un joker y ferait du client un redirecteur ouvert."
  }
}

variable "role_animateur" {
  description = <<-EOT
    Rôle de realm qui ouvre l'espace animateur, et la seule chose qu'il ouvre.

    Doit correspondre à OIDC_ANIMATEUR_ROLE côté application.
  EOT
  type        = string
  default     = "animateur"

  validation {
    condition     = !contains(["user", "admin", "mcp"], var.role_animateur)
    error_message = <<-EOT
      Ne peut pas valoir « user » : c'est le rôle que Keycloak accorde à tout
      le monde, et en faire l'accès animateur ouvrirait un espace à chaque
      compte du realm — y compris à ceux créés plus tard pour de tout autres
      raisons. Ni « admin » ni « mcp », qui ouvrent bien davantage.
    EOT
  }
}

# ------------------------------------------------------------------ clients --

variable "client_app" {
  description = "Identifiant du client OIDC de l'application web (OIDC_CLIENT_ID)."
  type        = string
  default     = "planning-app"
}

variable "client_app_secret" {
  description = <<-EOT
    Secret du client de l'application web, à passer par TF_VAR_client_app_secret.

    Au moins 32 caractères : c'est lui qui chiffre le vérificateur PKCE dans le
    cookie d'état. En deçà, Quarkus tire une clé au hasard à chaque démarrage,
    et une connexion entamée sur une instance ne peut plus s'achever sur une
    autre ni survivre à un redémarrage.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.client_app_secret) >= 32
    error_message = "Au moins 32 caractères — les secrets qu'engendre Keycloak en font exactement 32."
  }
}

variable "client_mcp" {
  description = "Client MCP automatisé, qui s'authentifie par client_credentials."
  type        = string
  default     = "planning-mcp-client"
}

variable "client_mcp_secret" {
  description = "Secret du client MCP automatisé, à passer par TF_VAR_client_mcp_secret."
  type        = string
  sensitive   = true
}

variable "client_mcp_resource" {
  description = <<-EOT
    La RESSOURCE MCP : elle n'émet aucun jeton, elle EST l'audience que /mcp
    exige (OIDC_MCP_AUDIENCE). Séparer la ressource du client est ce qui
    permet de refuser un jeton émis pour autre chose.
  EOT
  type        = string
  default     = "planning-mcp"
}

variable "client_provisioning" {
  description = "Compte de service par lequel l'application crée les comptes animateurs (OIDC_PROVISIONING_CLIENT_ID)."
  type        = string
  default     = "planning-provisioning"
}

variable "client_provisioning_secret" {
  description = "Secret du compte de service du provisioning, à passer par TF_VAR_client_provisioning_secret."
  type        = string
  sensitive   = true
}

variable "client_mcp_public_enabled" {
  description = "Client public + PKCE, pour un client MCP de bureau qui ouvre un navigateur. `false` : un client de moins, une surface de moins."
  type        = bool
  default     = true
}

variable "client_mcp_public_redirect_uris" {
  description = <<-EOT
    URI de redirection du client MCP interactif : une boucle locale. Keycloak
    accepte n'importe quel port sur 127.0.0.1 quand l'URI enregistrée n'en
    nomme pas (RFC 8252) ; il ne connaît pas de joker de port.
  EOT
  type        = list(string)
  default     = ["http://127.0.0.1/*", "http://localhost/*"]
}

# -------------------------------------------------------------------- durées --

variable "access_token_lifespan" {
  description = "Durée de vie d'un jeton d'accès."
  type        = string
  default     = "15m"
}

variable "sso_session_idle_timeout" {
  description = "Inactivité au bout de laquelle une session expire."
  type        = string
  default     = "30m"
}

variable "sso_session_max_lifespan" {
  description = "Durée maximale d'une session, activité ou non."
  type        = string
  default     = "8h"
}

# ---------------------------------------------------------- code par e-mail --

variable "code_email_validity_seconds" {
  description = "Validité du code envoyé par e-mail, en secondes."
  type        = number
  default     = 600
}

variable "code_email_max_attempts" {
  description = "Codes faux acceptés avant que le code ne soit brûlé."
  type        = number
  default     = 5
}

# ---------------------------------------------------------------------- SMTP --

variable "smtp" {
  description = <<-EOT
    Le relais par lequel Keycloak envoie invitations, réinitialisations,
    vérifications d'adresse ET les codes de connexion par e-mail.
    Obligatoire : sans lui, un compte créé est un compte que personne ne peut
    activer, et la méthode « code par e-mail » échoue à chaque essai.

    `ssl` (465, chiffré d'emblée) exclut `starttls` (587, élevé en cours de
    session) — les deux à la fois est une configuration contradictoire.
  EOT
  type = object({
    host              = string
    port              = optional(number, 587)
    from              = string
    from_display_name = optional(string)
    reply_to          = optional(string)
    envelope_from     = optional(string)
    starttls          = optional(bool, true)
    ssl               = optional(bool, false)
  })

  validation {
    condition     = !(var.smtp.ssl && var.smtp.starttls)
    error_message = "ssl (465) exclut starttls (587) : choisissez l'un ou l'autre."
  }
}

# Les identifiants du relais sont DEHORS de l'objet ci-dessus, et ce n'est pas
# une coquetterie de découpage. Un `password = "..."` dans un fichier
# d'exemple a la forme d'un secret quelle que soit sa valeur : les détecteurs
# le relèvent, et le fichier finit par apprendre aux gens à y écrire le vrai.
# Séparés, ils se passent par l'environnement :
#
#   export TF_VAR_smtp_username='planning@exemple.org'
#   export TF_VAR_smtp_password='...'

variable "smtp_username" {
  description = "Nom d'utilisateur du relais SMTP. `null` si le relais n'authentifie pas."
  type        = string
  default     = null
}

variable "smtp_password" {
  description = "Mot de passe du relais SMTP, à passer par TF_VAR_smtp_password."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = (var.smtp_username == null) == (var.smtp_password == null)
    error_message = "Un nom d'utilisateur SMTP sans mot de passe — ou l'inverse — n'authentifie rien."
  }
}

# ------------------------------------------------- autres moyens de connexion --

variable "recovery_codes_enabled" {
  description = "Rend disponible l'enrôlement de codes de secours — le filet quand un téléphone disparaît. Disponible, jamais imposé."
  type        = bool
  default     = false
}

variable "google_client_id" {
  description = <<-EOT
    Identifiant OAuth Google. `null` (défaut) : aucun fournisseur Google. Le
    secret se passe par TF_VAR_google_client_secret, et l'URI de redirection à
    déclarer chez Google est <keycloak_url>/realms/<realm>/broker/google/endpoint.
  EOT
  type        = string
  default     = null
}

variable "google_client_secret" {
  description = "Secret OAuth Google, à passer par TF_VAR_google_client_secret."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = (var.google_client_id == null) == (var.google_client_secret == null)
    error_message = "Google demande son identifiant ET son secret, ou aucun des deux."
  }
}

# ----------------------------------------- enregistrement dynamique (RFC 7591) --

variable "dynamic_client_registration" {
  description = <<-EOT
    Certains clients MCP n'acceptent pas de clientId pré-déclaré. Éteint par
    défaut : allumé, quiconque atteint le realm peut y créer un client.
  EOT
  type        = bool
  default     = false
}

variable "dcr_trusted_hosts" {
  description = <<-EOT
    Les hôtes autorisés à enregistrer un client. C'est ce qui rend l'option
    tenable — la laisser vide revient à ouvrir l'enregistrement à Internet.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !var.dynamic_client_registration || length(var.dcr_trusted_hosts) > 0
    error_message = "dynamic_client_registration = true exige dcr_trusted_hosts : sans liste, n'importe qui peut enregistrer un client."
  }
}
