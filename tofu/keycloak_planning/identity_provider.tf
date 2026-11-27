# Pocket ID (id.sylvain.cloud), fournisseur d'identité FÉDÉRÉ du realm : le
# bouton « Pocket ID » de la page de connexion. Il répète le chemin d'un
# client qui branche son annuaire (son ADFS demain) : l'appli ne voit que
# Keycloak (même émetteur, même client planning-app), Keycloak délègue
# l'authentification. README.md, « Fournisseur fédéré (Pocket ID) ».
#
# Le client côté Pocket ID (pocketid_client.flip_planning, réservé au groupe
# flip-planning) et son secret sont dans tofu/pangolin_config : son apply
# passe AVANT celui-ci, la sortie n'existe pas avant.
locals {
  pocket_id_issuer = "https://id.sylvain.cloud"
}

resource "keycloak_oidc_identity_provider" "pocket_id" {
  realm        = keycloak_realm.planning.id
  alias        = "pocket-id" # dans le rappel déclaré chez Pocket ID : ne pas changer seul
  display_name = "Pocket ID"
  provider_id  = "oidc"
  enabled      = true

  client_id     = "flip-planning"
  client_secret = data.terraform_remote_state.pangolin_config.outputs.pocket_id_flip_planning_client_secret

  # Points d'accès du document de découverte de Pocket ID.
  issuer             = local.pocket_id_issuer
  authorization_url  = "${local.pocket_id_issuer}/authorize"
  token_url          = "${local.pocket_id_issuer}/api/oidc/token"
  user_info_url      = "${local.pocket_id_issuer}/api/oidc/userinfo"
  jwks_url           = "${local.pocket_id_issuer}/.well-known/jwks.json"
  validate_signature = true
  # Pas de logout_url : se déconnecter de Flip Planning ne ferme que la session
  # Keycloak, jamais celle de Pocket ID (le mur Pangolin et les autres applis).
  default_scopes = "openid profile email"

  # Pocket ID marque les adresses vérifiées (l'admin les pose, les comptes ne
  # les modifient pas : ALLOW_OWN_ACCOUNT_EDIT=false) ; l'appli ne rattache que
  # sur email_verified. FORCE : nom et adresse relus à chaque connexion, comme
  # un annuaire qui fait foi.
  trust_email = true
  sync_mode   = "FORCE"
  store_token = false

  # Flux « first broker login » par défaut : une adresse déjà présente dans le
  # realm demande le mot de passe Keycloak pour lier ; sinon un compte Keycloak
  # est créé (sans droit dans l'appli tant qu'elle n'a pas de compte actif).
  extra_config = {
    pkceEnabled = "true"
    pkceMethod  = "S256"
  }
}
