# Realm `planning` du Keycloak de production de Flip Planning (conteneur
# flip-planning-keycloak, rôle flip_planning, sous /auth de
# flip-planning.sylvain.cloud). Ordre de mise en route et budget mémoire :
# README.md.
#
# Le realm porte ce que l'application attend d'un fournisseur OIDC
# (docs/oidc.md et docs/mcp.md du dépôt planning-equipes) et rien de plus :
# l'application décide des droits (table compte/habilitation), le realm dit
# seulement qui se connecte. Les PERSONNES n'y sont pas : comptes créés à la
# main dans la console (adresse vérifiée), voir README.md.

locals {
  public_url = "https://flip-planning.sylvain.cloud"
  # L'émetteur que l'application lie à chaque compte : le changer, c'est la
  # procédure « Changer l'URL du fournisseur » de docs/oidc.md.
  issuer = "${local.public_url}/auth/realms/${keycloak_realm.planning.realm}"

  # Les scopes que Keycloak pose par défaut sur un client, plus l'audience MCP.
  default_scopes = ["profile", "email", "roles", "web-origins", "acr", "basic", keycloak_openid_client_scope.mcp_audience.name]
}

resource "keycloak_realm" "planning" {
  realm        = "planning"
  display_name = "Flip Planning"
  enabled      = true

  # L'adresse est l'identité que l'application rapproche (claim `email`).
  login_with_email_allowed = true
  duplicate_emails_allowed = false
  # Personne ne s'inscrit seul : les comptes sont créés par un administrateur.
  registration_allowed  = false
  edit_username_allowed = false
  # Pas de relais SMTP branché : ni lien « mot de passe oublié », ni e-mail de
  # vérification. L'administrateur crée le compte avec l'adresse marquée
  # vérifiée (l'application ne rattache que sur email_verified) et un mot de
  # passe temporaire.
  reset_password_allowed = false
  verify_email           = false
  ssl_required           = "external"

  # Le jeton d'accès vit 5 minutes ; la session de l'application se prolonge
  # par le refresh token (quarkus.oidc.token.refresh-expired).
  access_token_lifespan    = "5m"
  sso_session_idle_timeout = "8h"
  sso_session_max_lifespan = "12h"

  password_policy = "length(12) and notUsername and notEmail and passwordHistory(3)"

  internationalization {
    supported_locales = ["fr", "en"]
    default_locale    = "fr"
  }

  # Le realm est public (chemins ouverts hors SSO Pangolin, website_flip_planning.tf) :
  # le formulaire est la seule porte, d'où le verrouillage temporaire.
  security_defenses {
    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 5
      wait_increment_seconds           = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
    }
    headers {
      x_frame_options                     = "SAMEORIGIN"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      x_xss_protection                    = "1; mode=block"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
      referrer_policy                     = "no-referrer"
    }
  }

  # Les événements d'administration ne se gardent que 7 jours, comme ceux des
  # utilisateurs : Keycloak ne porte cette durée que dans les attributs.
  attributes = {
    adminEventsExpiration = "604800"
  }
}

# Connexions, échecs et changements d'administration lisibles dans la console
# (Événements), 7 jours : adresses, IP, horodatages, rien à garder au-delà.
resource "keycloak_realm_events" "planning" {
  realm_id = keycloak_realm.planning.id

  events_enabled               = true
  events_expiration            = 604800
  enabled_event_types          = []
  events_listeners             = ["jboss-logging"]
  admin_events_enabled         = true
  admin_events_details_enabled = true
}

# ------------------------------------------------------- application web --

resource "keycloak_openid_client" "app" {
  realm_id    = keycloak_realm.planning.id
  client_id   = "planning-app"
  name        = "Flip Planning"
  description = "Client confidentiel du code flow, PKCE S256 : la connexion à l'application."
  enabled     = true

  access_type   = "CONFIDENTIAL"
  client_secret = local.oidc_client_secret

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # EXACTES, sans joker (docs/oidc.md) : le redirect_uri envoyé suit l'en-tête
  # Host de la requête, un joker laisserait un hôte inattendu recevoir le code.
  # La route de connexion fait aussi office de retour du code.
  valid_redirect_uris             = ["${local.public_url}/api/auth/oidc/login"]
  valid_post_logout_redirect_uris = ["${local.public_url}/login"]
  web_origins                     = [local.public_url]

  # Doit s'accorder avec quarkus.oidc.authentication.pkce-required=true.
  pkce_code_challenge_method = "S256"
}

# ---------------------------------------------------------- audience MCP --

# Le serveur MCP n'accepte qu'un jeton portant l'audience planning-mcp
# (OIDC_MCP_AUDIENCE) : sans elle, un jeton obtenu pour n'importe quel client
# du realm ouvrirait les outils. Ce client n'émet rien, il EST l'audience.
resource "keycloak_openid_client" "mcp_resource" {
  realm_id    = keycloak_realm.planning.id
  client_id   = "planning-mcp"
  name        = "Flip Planning — serveur MCP (resource server)"
  description = "N'émet aucun jeton : il est l'audience que /mcp exige."
  enabled     = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
}

resource "keycloak_openid_client_scope" "mcp_audience" {
  realm_id               = keycloak_realm.planning.id
  name                   = "planning-mcp-audience"
  description            = "Ajoute l'audience planning-mcp aux jetons d'accès, ce que /mcp exige."
  include_in_token_scope = false
}

resource "keycloak_openid_audience_protocol_mapper" "mcp_audience" {
  realm_id                 = keycloak_realm.planning.id
  client_scope_id          = keycloak_openid_client_scope.mcp_audience.id
  name                     = "planning-mcp-audience"
  included_client_audience = keycloak_openid_client.mcp_resource.client_id
  add_to_access_token      = true
  add_to_id_token          = false
}

# Scopes par défaut des clients CRÉÉS ENSUITE, donc de ceux que les clients MCP
# hébergés enregistrent dynamiquement : ils n'existent pas encore ici et
# n'obtiendraient l'audience par aucun autre moyen.
resource "keycloak_realm_default_client_scopes" "planning" {
  realm_id       = keycloak_realm.planning.id
  default_scopes = local.default_scopes
}

# ----------------------------------- enregistrement dynamique (RFC 7591) --
#
# Claude sur le web et Le Chat enregistrent eux-mêmes leur client, sans jeton
# (anonyme), depuis leurs serveurs. Keycloak pose à la création du realm des
# politiques « anonymous » dont « Trusted Hosts » à liste VIDE, qui refuse
# tout : l'enregistrement est fermé tant que var.dcr_trusted_hosts est vide.
#
# Ouvert, le réglage est :
#   - Trusted Hosts : seules les URI de redirection (redirect_uris) sur ces
#     hôtes passent (client-uris-must-match), quel que soit l'appelant
#     (host-sending-registration-request-must-match faux : les serveurs des
#     assistants n'ont pas d'adresse stable à nommer). Un client enregistré ne
#     peut donc renvoyer un code que chez l'assistant, jamais chez un tiers.
#   - Consent Required, Allowed Client Scopes, Allowed Protocol Mapper Types,
#     Full Scope Disabled : les politiques par défaut de Keycloak, laissées en
#     place (écran de consentement, pas de scope ni de mappeur arbitraire).
#   - Max Clients : 20 au lieu de 200.
# Un client enregistré n'ouvre rien seul : il faut encore une personne qui se
# connecte au realm ET un compte actif portant un droit dans l'application.
#
# Les deux politiques existent déjà (créées avec le realm) : Tofu les PREND en
# main par `tofu import` (README.md), un second composant du même type
# s'ajouterait au premier, et la liste vide de celui-ci refuserait toujours.
resource "keycloak_realm_client_registration_policy" "trusted_hosts" {
  count = length(var.dcr_trusted_hosts) > 0 ? 1 : 0

  realm_id    = keycloak_realm.planning.id
  name        = "Trusted Hosts"
  provider_id = "trusted-hosts"
  sub_type    = "anonymous"

  config = {
    "trusted-hosts"                                = join("##", var.dcr_trusted_hosts)
    "host-sending-registration-request-must-match" = "false"
    "client-uris-must-match"                       = "true"
  }
}

resource "keycloak_realm_client_registration_policy" "max_clients" {
  count = length(var.dcr_trusted_hosts) > 0 ? 1 : 0

  realm_id    = keycloak_realm.planning.id
  name        = "Max Clients Limit"
  provider_id = "max-clients"
  sub_type    = "anonymous"

  config = {
    "max-clients" = "20"
  }
}
