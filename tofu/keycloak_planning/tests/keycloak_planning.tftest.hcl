# Realm planning du Keycloak de production de Flip Planning. Tout est mocké :
# aucune connexion à Keycloak, à S3 ni à SOPS.

variables {
  state_encryption_passphrase      = "tofu-test-passphrase-not-a-secret"
  pangolin_config_state_passphrase = "tofu-test-passphrase-not-a-secret"
}

mock_provider "keycloak" {}
mock_provider "sops" {}

override_data {
  target = data.sops_file.ansible
  values = {
    data = {
      prod_planning_keycloak_admin_password = "fake-admin-password"
      prod_planning_oidc_client_secret      = "fake-client-secret-of-at-least-32-chars"
    }
  }
}

override_data {
  target = data.terraform_remote_state.pangolin_config
  values = {
    outputs = {
      flip_planning_access_token = "{\"id\":\"42\",\"token\":\"fake-token\"}"
    }
  }
}

run "client_de_l_application" {
  command = plan

  # docs/oidc.md : URI exactes, sans joker, PKCE, client confidentiel.
  assert {
    condition = (
      keycloak_openid_client.app.client_id == "planning-app"
      && keycloak_openid_client.app.access_type == "CONFIDENTIAL"
      && keycloak_openid_client.app.pkce_code_challenge_method == "S256"
      && keycloak_openid_client.app.valid_redirect_uris == toset(["https://flip-planning.sylvain.cloud/api/auth/oidc/login"])
      && keycloak_openid_client.app.valid_post_logout_redirect_uris == toset(["https://flip-planning.sylvain.cloud/login"])
      && !keycloak_openid_client.app.direct_access_grants_enabled
      && !keycloak_openid_client.app.implicit_flow_enabled
    )
    error_message = "planning-app : confidentiel, PKCE S256, redirections exactes /api/auth/oidc/login et /login, ni mot de passe direct ni flux implicite."
  }

  assert {
    condition     = output.issuer == "https://flip-planning.sylvain.cloud/auth/realms/planning"
    error_message = "L'émetteur est figé : le changer impose la procédure « Changer l'URL du fournisseur » de l'application."
  }

  assert {
    condition     = !keycloak_realm.planning.registration_allowed
    error_message = "Personne ne s'inscrit seul dans le realm."
  }

  # Le provider passe le SSO Pangolin avec le jeton de la ressource.
  assert {
    condition     = local.pangolin_access_headers == { "P-Access-Token-Id" = "42", "P-Access-Token" = "fake-token" }
    error_message = "En-têtes d'accès Pangolin mal tirés de la sortie flip_planning_access_token."
  }
}

run "audience_mcp" {
  command = plan

  assert {
    condition = (
      keycloak_openid_client.mcp_resource.client_id == "planning-mcp"
      && keycloak_openid_audience_protocol_mapper.mcp_audience.included_client_audience == "planning-mcp"
      && keycloak_openid_audience_protocol_mapper.mcp_audience.add_to_access_token
      && contains(keycloak_realm_default_client_scopes.planning.default_scopes, "planning-mcp-audience")
    )
    error_message = "Les jetons d'accès des clients (dont ceux enregistrés dynamiquement) doivent porter l'audience planning-mcp (OIDC_MCP_AUDIENCE)."
  }
}

run "enregistrement_dynamique_ferme_si_vide" {
  command = plan

  variables {
    dcr_trusted_hosts = []
  }

  assert {
    condition     = length(keycloak_realm_client_registration_policy.trusted_hosts) == 0 && length(keycloak_realm_client_registration_policy.max_clients) == 0
    error_message = "Sans hôte de confiance, Tofu ne touche pas aux politiques : la liste vide de Keycloak ferme l'enregistrement anonyme."
  }
}

run "enregistrement_dynamique_ouvert_par_defaut_aux_assistants" {
  command = plan

  assert {
    condition     = keycloak_realm_client_registration_policy.trusted_hosts[0].config["trusted-hosts"] == "claude.ai##claude.com##chat.mistral.ai"
    error_message = "Par défaut, seuls Claude (web) et Le Chat peuvent enregistrer un client."
  }

  assert {
    condition     = length(keycloak_realm_optional_client_scopes.planning.optional_scopes) == 0
    error_message = "Aucun scope optionnel, offline_access compris : un client enregistré par n'importe qui ne doit pas obtenir de jeton hors session."
  }
}

run "enregistrement_dynamique_borne" {
  command = plan

  variables {
    dcr_trusted_hosts = ["claude.ai", "chat.mistral.ai"]
  }

  assert {
    condition = (
      keycloak_realm_client_registration_policy.trusted_hosts[0].config["trusted-hosts"] == "claude.ai##chat.mistral.ai"
      && keycloak_realm_client_registration_policy.trusted_hosts[0].config["client-uris-must-match"] == "true"
      && keycloak_realm_client_registration_policy.trusted_hosts[0].sub_type == "anonymous"
      && keycloak_realm_client_registration_policy.max_clients[0].config["max-clients"] == "20"
    )
    error_message = "Enregistrement ouvert : URI de redirection limitées aux hôtes de confiance, 20 clients au plus."
  }
}

run "pas_de_joker_dans_les_hotes" {
  command = plan

  variables {
    dcr_trusted_hosts = ["*.example.com"]
  }

  expect_failures = [var.dcr_trusted_hosts]
}
