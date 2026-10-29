# ------------------------------------------------------------------- realm --

resource "keycloak_realm" "planning" {
  realm        = var.realm
  display_name = var.realm_display_name
  enabled      = true

  # Connexion par e-mail : c'est l'adresse de la fiche animateur qui sert
  # d'identité, et c'est elle que l'application rapproche.
  login_with_email_allowed = true
  # L'exact contraire n'est pas disponible : Keycloak refuse de combiner
  # « doublons d'e-mail autorisés » et « connexion par e-mail ». Un compte est
  # donc une PERSONNE, pas une fiche — un animateur présent sur deux éditions
  # garde un seul compte. Voir docs/keycloak.md.
  duplicate_emails_allowed = false
  # Personne ne s'inscrit tout seul dans le realm d'un planning : les comptes
  # viennent des fiches (provisioning), du playbook des personnes, ou de la
  # console.
  registration_allowed   = false
  reset_password_allowed = true
  edit_username_allowed  = false
  # L'espace animateur ne s'ouvre que sur une adresse VÉRIFIÉE : c'est le
  # rapprochement avec la fiche qui en dépend.
  verify_email = true
  ssl_required = "external"

  access_token_lifespan    = var.access_token_lifespan
  sso_session_idle_timeout = var.sso_session_idle_timeout
  sso_session_max_lifespan = var.sso_session_max_lifespan
  # Le lien d'une invitation vit 48 h, pas les 12 h par défaut : un animateur
  # ne lit pas toujours ses mails le jour même.
  action_token_generated_by_admin_lifespan = "48h"

  # Pages et e-mails en français : sans langue par défaut, Keycloak écrit en
  # anglais — l'invitation comme le code de connexion. L'anglais reste au choix
  # de la personne sur la page de connexion.
  internationalization {
    supported_locales = ["fr", "en"]
    default_locale    = "fr"
  }

  # Le thème « planning » de l'image du dépôt : page de connexion, console de
  # compte et e-mails aux couleurs du produit, visuels du client montés dans
  # brand/.
  login_theme   = var.login_theme
  account_theme = var.account_theme
  email_theme   = var.email_theme

  # Les événements d'administration ne se gardent que 7 jours, comme ceux des
  # utilisateurs (keycloak_realm_events) : Keycloak ne porte cette durée que
  # dans les attributs du realm.
  attributes = {
    adminEventsExpiration = tostring(var.events_expiration_seconds)
  }

  otp_policy {
    type      = "totp"
    algorithm = "HmacSHA1"
    digits    = 6
    period    = 30
  }

  # Un passkey, pas une simple clé de second facteur : la clé porte l'identité
  # (résidente) et son déverrouillage prouve qu'une personne est là
  # (vérification exigée). Même politique que le realm de développement.
  # discoverable_credential remplace require_resident_key, déprécié : il
  # demande Keycloak 26.7 et le fournisseur 5.9.
  web_authn_passwordless_policy {
    relying_party_entity_name         = var.realm_display_name
    signature_algorithms              = ["ES256", "RS256"]
    discoverable_credential           = "required"
    user_verification_requirement     = "required"
    attestation_conveyance_preference = "none"
    # Le téléphone propose sa passkey dès l'écran de l'adresse, qu'il n'y a
    # alors même pas à taper. Taper l'adresse reste possible, et mène au code
    # par e-mail quand la passkey est perdue.
    passwordless_passkeys_enabled = true
  }

  smtp_server {
    host              = var.smtp.host
    port              = var.smtp.port
    from              = var.smtp.from
    from_display_name = var.smtp.from_display_name
    reply_to          = var.smtp.reply_to
    envelope_from     = var.smtp.envelope_from
    starttls          = var.smtp.starttls
    ssl               = var.smtp.ssl

    # Les identifiants ne sont écrits QUE si l'on en a donné : un nom
    # d'utilisateur posé à côté d'un relais qui ne demande rien est au mieux
    # du bruit, au pire un mot de passe stocké dans un realm qui ne s'en sert
    # pas.
    dynamic "auth" {
      for_each = var.smtp_username == null ? [] : [1]
      content {
        username = var.smtp_username
        password = var.smtp_password
      }
    }
  }
}

# ------------------------------------------------------------------- rôles --

# Ce sont EXACTEMENT les rôles de docker/keycloak/realm-planning.json, et ceux
# que l'application connaît (application.properties : role-admin, cle-mcp,
# OIDC_ANIMATEUR_ROLE). En ajouter un ici sans le déclarer là-bas donne un
# rôle qui n'ouvre rien.
resource "keycloak_role" "admin" {
  realm_id    = keycloak_realm.planning.id
  name        = "admin"
  description = "Administration complète : /api/*, /q/openapi. Second facteur TOTP imposé par le flow browser-planning, quelle que soit la méthode de connexion."
}

resource "keycloak_role" "animateur" {
  realm_id    = keycloak_realm.planning.id
  name        = var.role_animateur
  description = "Ouvre l'espace de sa propre fiche, et rien d'autre. Distinct de « user » à dessein : un privilège bâti sur le rôle ordinaire serait hérité par tout compte futur."
}

resource "keycloak_role" "user" {
  realm_id = keycloak_realm.planning.id
  name     = "user"
  # Keycloak stocke une description en VARCHAR(255) et ne tronque pas : au-delà,
  # l'API répond 500 et la seule trace est un « Value too long for column
  # DESCRIPTION » dans le journal de l'autre programme.
  description = "Rôle ordinaire du realm : N'OUVRE RIEN. Un compte qui ne porte que lui atteint une page le disant. Bâtir un privilège sur « cette personne existe » est un privilège que tout compte futur hérite sans que personne l'accorde."
}

resource "keycloak_role" "mcp" {
  realm_id    = keycloak_realm.planning.id
  name        = "mcp"
  description = "Serveur MCP : /mcp uniquement, jamais /api. Porté par le client automatisé ou par une personne qui passe par un client MCP interactif."
}

# ------------------------------------------------------- audience du MCP --

# Le resource server n'accepte que les jetons émis POUR lui
# (quarkus.oidc.mcptransport.token.audience). Sans ce scope, un jeton obtenu pour
# n'importe quel autre client du realm ouvrirait les outils MCP.
#
# Un client scope ici, un mappeur posé sur chaque client dans le realm JSON :
# ce n'est pas une incohérence. Le fichier importé ne peut PAS déclarer de
# `clientScopes` (il remplacerait les scopes intégrés au lieu de s'y ajouter,
# voir docs/keycloak.md), alors que Terraform parle à un realm déjà peuplé.
resource "keycloak_openid_client_scope" "mcp_audience" {
  realm_id    = keycloak_realm.planning.id
  name        = "planning-mcp-audience"
  description = "Ajoute l'audience ${var.client_mcp_resource} aux jetons, ce que le serveur MCP exige."

  # Il n'y a rien à consentir, et le scope n'a pas à figurer dans le claim
  # `scope` d'un jeton.
  include_in_token_scope = false
}

resource "keycloak_openid_audience_protocol_mapper" "mcp_audience" {
  realm_id        = keycloak_realm.planning.id
  client_scope_id = keycloak_openid_client_scope.mcp_audience.id
  name            = "planning-mcp-audience"

  included_client_audience = keycloak_openid_client.mcp_resource.client_id

  # Dans le jeton d'ACCÈS seulement : c'est celui que le resource server
  # reçoit. Le jeton d'identité ne sort jamais de l'application web.
  add_to_access_token = true
  add_to_id_token     = false
}

# ----------------------------------------------------------------- clients --

resource "keycloak_openid_client" "app" {
  realm_id  = keycloak_realm.planning.id
  client_id = var.client_app
  # Le nom que la console de compte affiche dans « Retour à … ».
  name        = "Planning Équipes"
  description = "Client confidentiel du code flow, PKCE S256 exigé : c'est lui que Quarkus utilise pour connecter administrateurs et animateurs."
  enabled     = true

  access_type   = "CONFIDENTIAL"
  client_secret = var.client_app_secret

  standard_flow_enabled = true
  implicit_flow_enabled = false
  # L'application ne reçoit jamais les identifiants de personne : elle mène un
  # code flow. Activer ce grant ferait d'elle un endroit où un mot de passe
  # peut transiter, ce qui est toute la chose évitée.
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris             = ["${var.planning_public_url}/*"]
  valid_post_logout_redirect_uris = ["${var.planning_public_url}/*"]
  web_origins                     = [var.planning_public_url]

  # Doit s'accorder avec `quarkus.oidc.authentication.pkce-required=true` côté
  # application. Déclaré d'un seul côté, il tue toutes les connexions AVANT
  # l'écran de connexion, sur « Missing parameter: code_challenge_method ».
  pkce_code_challenge_method = "S256"
}

resource "keycloak_openid_client" "mcp_resource" {
  realm_id    = keycloak_realm.planning.id
  client_id   = var.client_mcp_resource
  name        = "Planning Équipes — serveur MCP (resource server)"
  description = "N'émet aucun jeton : il EST l'audience que /mcp exige. Séparer la ressource du client est ce qui permet de refuser un jeton émis pour autre chose."
  enabled     = true

  # Aucun flux : ce client ne s'authentifie jamais, il est seulement nommé dans
  # le claim `aud` des jetons des autres.
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
}

resource "keycloak_openid_client" "mcp" {
  realm_id    = keycloak_realm.planning.id
  client_id   = var.client_mcp
  name        = "Planning Équipes — client MCP automatisé"
  description = "client_credentials pour un assistant qui tourne sans humain. Rôle mcp, jamais admin : il ouvre /mcp et rien d'autre."
  enabled     = true

  access_type   = "CONFIDENTIAL"
  client_secret = var.client_mcp_secret

  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true
}

resource "keycloak_openid_client" "mcp_public" {
  count = var.client_mcp_public_enabled ? 1 : 0

  realm_id    = keycloak_realm.planning.id
  client_id   = "planning-mcp-public"
  name        = "Planning Équipes — client MCP interactif"
  description = "Client public + PKCE, pour un client MCP de bureau qui ouvre un navigateur et écoute sur une boucle locale."
  enabled     = true

  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris        = var.client_mcp_public_redirect_uris
  pkce_code_challenge_method = "S256"
}

resource "keycloak_openid_client" "provisioning" {
  realm_id    = keycloak_realm.planning.id
  client_id   = var.client_provisioning
  name        = "Planning Équipes — provisioning des comptes"
  description = "Compte de service par lequel l'application crée les comptes animateurs. manage-users sur ce realm, rien de plus : il ne peut ni lire les jetons, ni toucher aux clients."
  enabled     = true

  access_type   = "CONFIDENTIAL"
  client_secret = var.client_provisioning_secret

  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true
}

# -------------------------------------------- où l'audience est servie --

# Sur les deux clients MCP, et — si le DCR est allumé — sur le realm : un
# client enregistré dynamiquement n'existe pas encore quand ce code tourne, et
# n'obtiendrait l'audience par aucun autre moyen.
resource "keycloak_openid_client_default_scopes" "mcp" {
  realm_id  = keycloak_realm.planning.id
  client_id = keycloak_openid_client.mcp.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.mcp_audience.name,
  ]
}

resource "keycloak_openid_client_default_scopes" "mcp_public" {
  count = var.client_mcp_public_enabled ? 1 : 0

  realm_id  = keycloak_realm.planning.id
  client_id = keycloak_openid_client.mcp_public[0].id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.mcp_audience.name,
  ]
}

resource "keycloak_realm_default_client_scopes" "dcr" {
  count = var.dynamic_client_registration ? 1 : 0

  realm_id = keycloak_realm.planning.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.mcp_audience.name,
  ]
}

# --------------------------------------- droits des comptes de service --

data "keycloak_openid_client" "realm_management" {
  realm_id  = keycloak_realm.planning.id
  client_id = "realm-management"
}

# Gérer les utilisateurs, et seulement eux. Pas `view-realm` : l'application
# cherche le rôle animateur parmi ceux assignables à l'utilisateur, ce que
# manage-users couvre. Élargir ici élargirait ce qu'un secret fuité ouvre.
resource "keycloak_openid_client_service_account_role" "provisioning" {
  for_each = toset(["manage-users", "view-users", "query-users"])

  realm_id                = keycloak_realm.planning.id
  service_account_user_id = keycloak_openid_client.provisioning.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = each.value
}

# Le rôle `mcp`, jamais `admin` : porter le rôle d'administration n'est pas
# porter celui du serveur MCP.
resource "keycloak_openid_client_service_account_realm_role" "mcp" {
  realm_id                = keycloak_realm.planning.id
  service_account_user_id = keycloak_openid_client.mcp.service_account_user_id
  role                    = keycloak_role.mcp.name
}

# ----------------------------------------------------- flow de connexion --

# L'adresse d'abord, la méthode ensuite, et le second facteur des
# administrateurs après N'IMPORTE QUELLE méthode. C'est, nœud pour nœud,
# l'arbre de docker/keycloak/realm-planning.json :
#
#   browser-planning
#   ├── auth-cookie                              ALTERNATIVE
#   ├── identity-provider-redirector             ALTERNATIVE
#   └── browser-planning-forms                   ALTERNATIVE
#       ├── auth-username-form                   REQUIRED     l'adresse, seule
#       ├── browser-planning-methodes            REQUIRED
#       │   ├── webauthn-authenticator-passwordless ALTERNATIVE  passkey
#       │   ├── browser-planning-code-email      ALTERNATIVE
#       │   │   └── planning-code-email          REQUIRED     l'extension de l'image
#       │   └── auth-password-form               ALTERNATIVE
#       └── browser-planning-otp-admin           CONDITIONAL
#           ├── conditional-user-role (admin)    REQUIRED
#           └── auth-otp-form                    REQUIRED
#
# LE FLUX EST ÉCRIT EN ENTIER, ET CE N'EST PAS UN CHOIX DE STYLE.
#
# `copy_from = "browser"` semble plus sûr : il reprend la chaîne native sans
# risquer d'en perdre un maillon. Essayé, et le résultat ne marche pas. La
# copie ne donne aucun moyen de viser l'intérieur de son sous-flux « forms »
# autrement qu'en devinant l'alias que Keycloak lui donne, si bien que le
# sous-flux conditionnel atterrit au PREMIER NIVEAU — avant le formulaire,
# donc avant qu'un utilisateur existe. Or la condition porte sur le rôle de
# cet utilisateur : elle ne peut pas s'évaluer, et le second facteur n'est
# jamais demandé. Rien ne le signale.
#
# Le sous-flux conditionnel pend du sous-flux « forms », APRÈS les méthodes :
# accroché sous le seul mot de passe, il laisserait un administrateur entrer
# par le code e-mail — un seul facteur, la boîte aux lettres — sans TOTP.
#
# Changer cette structure sur un realm en service : Keycloak refuse de
# supprimer un flux lié (« Cannot remove authentication flow, it is currently
# in use »). Rendre d'abord browser_flow au flux natif, appliquer, puis
# appliquer la nouvelle structure — docs/keycloak.md.

resource "keycloak_authentication_flow" "browser_planning" {
  realm_id    = keycloak_realm.planning.id
  alias       = "browser-planning"
  description = "Connexion navigateur : session existante, fournisseur externe, ou l'adresse puis une méthode. Écrit en entier, jamais copié du flow natif."
}

# Une session déjà ouverte court-circuite tout le reste.
resource "keycloak_authentication_execution" "cookie" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_flow.browser_planning.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

# Ce qui rend un fournisseur externe (Google, un annuaire) branchable sans
# retoucher au flux.
resource "keycloak_authentication_execution" "idp_redirector" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_flow.browser_planning.alias
  authenticator     = "identity-provider-redirector"
  requirement       = "ALTERNATIVE"
  priority          = 20

  depends_on = [keycloak_authentication_execution.cookie]
}

resource "keycloak_authentication_subflow" "forms" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_flow.browser_planning.alias
  alias             = "browser-planning-forms"
  description       = "L'adresse d'abord, puis une méthode, puis le second facteur des administrateurs, quelle que soit la méthode choisie."
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 30

  depends_on = [keycloak_authentication_execution.idp_redirector]
}

# L'adresse seule : c'est ce qui permet de proposer ensuite ce dont CE compte
# dispose — passkey, code, mot de passe.
resource "keycloak_authentication_execution" "username_form" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.forms.alias
  authenticator     = "auth-username-form"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_subflow" "methodes" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.forms.alias
  alias             = "browser-planning-methodes"
  description       = "Les méthodes, en alternatives : passkey, code par e-mail ou mot de passe. La première qui aboutit identifie la personne."
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 20

  depends_on = [keycloak_authentication_execution.username_form]
}

resource "keycloak_authentication_execution" "passkey" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.methodes.alias
  authenticator     = "webauthn-authenticator-passwordless"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

# Un sous-flux pour une seule étape : l'authentificateur de l'extension
# n'accepte que REQUIRED ou DISABLED (EmailCodeAuthenticatorFactory), le choix
# entre méthodes se fait un niveau plus haut.
resource "keycloak_authentication_subflow" "code_email" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.methodes.alias
  alias             = "browser-planning-code-email"
  description       = "Code à six chiffres envoyé à l'adresse du compte (extension keycloak/code-email). Sous-flux à part : l'authentificateur n'accepte que REQUIRED."
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 20

  depends_on = [keycloak_authentication_execution.passkey]
}

# `planning-code-email` n'existe que dans l'image du dépôt
# (docker/keycloak/Dockerfile). Sur un Keycloak qui ne porte pas le JAR,
# l'apply échoue ici en nommant un fournisseur inconnu — le bon échec : une
# méthode proposée à l'écran et morte à l'usage serait pire.
resource "keycloak_authentication_execution" "code_email" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.code_email.alias
  authenticator     = "planning-code-email"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "code_email" {
  realm_id     = keycloak_realm.planning.id
  execution_id = keycloak_authentication_execution.code_email.id
  alias        = "code-email-planning"

  config = {
    validiteSecondes = tostring(var.code_email_validity_seconds)
    essaisMax        = tostring(var.code_email_max_attempts)
  }
}

resource "keycloak_authentication_execution" "password_form" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.methodes.alias
  authenticator     = "auth-password-form"
  requirement       = "ALTERNATIVE"
  priority          = 30

  depends_on = [keycloak_authentication_execution.code_email]
}

# APRÈS les méthodes, dans « forms » : la condition porte sur le rôle de la
# personne qui vient de s'identifier, et elle vaut quelle que soit la méthode.
resource "keycloak_authentication_subflow" "otp_admin" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.forms.alias
  alias             = "browser-planning-otp-admin"
  description       = "Conditionnel : pour le rôle admin seulement, un code TOTP après n'importe quelle méthode. Un admin sans TOTP se voit imposer CONFIGURE_TOTP."
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 30

  depends_on = [keycloak_authentication_execution.password_form]
}

resource "keycloak_authentication_execution" "condition_role_admin" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.otp_admin.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "condition_role_admin" {
  realm_id     = keycloak_realm.planning.id
  execution_id = keycloak_authentication_execution.condition_role_admin.id
  alias        = "condition-role-admin"

  config = {
    condUserRole = keycloak_role.admin.name
    negate       = "false"
  }
}

resource "keycloak_authentication_execution" "otp_form" {
  realm_id          = keycloak_realm.planning.id
  parent_flow_alias = keycloak_authentication_subflow.otp_admin.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 20

  depends_on = [keycloak_authentication_execution.condition_role_admin]
}

resource "keycloak_authentication_bindings" "planning" {
  realm_id     = keycloak_realm.planning.id
  browser_flow = keycloak_authentication_flow.browser_planning.alias

  # Le flux doit être entièrement bâti avant qu'on le lie : lier d'abord
  # exposerait un flux à moitié monté aux connexions en cours.
  depends_on = [
    keycloak_authentication_execution.cookie,
    keycloak_authentication_execution.idp_redirector,
    keycloak_authentication_execution.username_form,
    keycloak_authentication_execution.passkey,
    keycloak_authentication_execution_config.code_email,
    keycloak_authentication_execution.password_form,
    keycloak_authentication_execution_config.condition_role_admin,
    keycloak_authentication_execution.otp_form,
  ]
}

# ------------------------------------------------- actions d'enrôlement --

# Disponibles, jamais imposées : `default_action = false`. Une action par
# défaut barrerait la route à la première connexion de chacun pour enrôler un
# matériel que tout le monde n'a pas. CONFIGURE_TOTP, VERIFY_EMAIL et
# UPDATE_PASSWORD sont les actions intégrées, laissées telles quelles.
resource "keycloak_required_action" "passkey" {
  realm_id       = keycloak_realm.planning.realm
  alias          = "webauthn-register-passwordless"
  name           = "Webauthn Register Passwordless"
  enabled        = true
  default_action = false
  priority       = 60
}

resource "keycloak_required_action" "recovery_codes" {
  realm_id       = keycloak_realm.planning.realm
  alias          = "CONFIGURE_RECOVERY_AUTHN_CODES"
  name           = "Recovery Authentication Codes"
  enabled        = var.recovery_codes_enabled
  default_action = false
  priority       = 70
}

# -------------------------------------------------------------- événements --

# Qui s'est connecté, qui a échoué, qui a changé quoi dans le realm : de quoi
# répondre à « je n'arrive pas à me connecter » ou « qui a retiré ce rôle ? »
# depuis la console (Événements), sans fouiller les journaux du serveur.
# Gardés 7 jours, pas plus : ce sont des adresses, des IP et des horodatages,
# des données personnelles qui n'ont rien à faire là passé le diagnostic.
resource "keycloak_realm_events" "planning" {
  realm_id = keycloak_realm.planning.id

  events_enabled    = true
  events_expiration = var.events_expiration_seconds
  # Vide : tous les types d'événements utilisateur.
  enabled_event_types = []
  events_listeners    = ["jboss-logging"]

  admin_events_enabled = true
  # La représentation de l'objet modifié (le corps de la requête
  # d'administration), sans quoi un événement dit « un utilisateur a été mis
  # à jour » sans dire comment.
  admin_events_details_enabled = true
}

# ------------------------------------------------- profil utilisateur --

# Nom, prénom et adresse viennent de la fiche de l'organisation : la console
# de compte les montre, sans les laisser modifier (`edit = ["admin"]`, ce
# qu'écrit le compte de service du provisioning). Le mot de passe, la passkey
# et le second facteur, eux, restent à la personne. Nom et prénom ne sont pas
# exigés : un administrateur invité par sa seule adresse n'est pas arrêté à
# la connexion par un formulaire qu'il ne peut pas remplir.
resource "keycloak_realm_user_profile" "planning" {
  realm_id = keycloak_realm.planning.id

  attribute {
    name         = "username"
    display_name = "$${username}"
    multi_valued = false

    validator {
      name = "length"

      config = {
        min = "3"
        max = "255"
      }
    }

    validator {
      name = "username-prohibited-characters"
    }

    validator {
      name = "up-username-not-idn-homograph"
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin"]
    }
  }

  attribute {
    name               = "email"
    display_name       = "$${email}"
    multi_valued       = false
    required_for_roles = ["user"]

    validator {
      name = "email"
    }

    validator {
      name = "length"

      config = {
        max = "255"
      }
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin"]
    }
  }

  attribute {
    name         = "firstName"
    display_name = "$${firstName}"
    multi_valued = false

    validator {
      name = "length"

      config = {
        max = "255"
      }
    }

    validator {
      name = "person-name-prohibited-characters"
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin"]
    }
  }

  attribute {
    name         = "lastName"
    display_name = "$${lastName}"
    multi_valued = false

    validator {
      name = "length"

      config = {
        max = "255"
      }
    }

    validator {
      name = "person-name-prohibited-characters"
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin"]
    }
  }

  group {
    name                = "user-metadata"
    display_header      = "User metadata"
    display_description = "Attributes, which refer to user metadata"
  }
}

# ------------------------------------------------------------------ Google --

# `trust_email = false` est le cœur de cette ressource. Avec la confiance,
# quiconque peut créer un compte Google portant l'adresse d'un animateur se
# verrait remettre le compte de cet animateur à la première connexion. Sans
# elle, Keycloak déroule son flow « first broker login », qui fait prouver la
# détention du compte existant avant de lier les deux.
resource "keycloak_oidc_google_identity_provider" "google" {
  count = var.google_client_id == null ? 0 : 1

  realm                         = keycloak_realm.planning.id
  client_id                     = var.google_client_id
  client_secret                 = var.google_client_secret
  trust_email                   = false
  store_token                   = false
  sync_mode                     = "IMPORT"
  first_broker_login_flow_alias = "first broker login"
}

# ------------------------------------ enregistrement dynamique (RFC 7591) --

resource "keycloak_realm_client_registration_policy" "trusted_hosts" {
  count = var.dynamic_client_registration ? 1 : 0

  realm_id    = keycloak_realm.planning.id
  name        = "Trusted Hosts"
  provider_id = "trusted-hosts"
  sub_type    = "anonymous"

  config = {
    "trusted-hosts"                                = join("##", var.dcr_trusted_hosts)
    "host-sending-registration-request-must-match" = "true"
    "client-uris-must-match"                       = "true"
  }
}
