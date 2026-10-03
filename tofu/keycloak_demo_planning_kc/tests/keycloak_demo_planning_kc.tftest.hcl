# Realm Keycloak du banc demo-planning-kc (planning-equipes#72).
#
# Le module distant (terraform/keycloak de planning-equipes) porte son propre
# bloc provider "keycloak", que mock_provider ne remplace pas : seuls les
# providers du module racine sont mockés. override_module le court-circuite
# entièrement (aucune ressource planifiée, provider jamais configuré, donc
# aucune connexion à https://demo-planning-kc.sylvain.dev/auth). Ses
# variables, elles, restent évaluées avec leurs validations : c'est ce qui
# vérifie que les entrées passées par main.tf (URL publique, SMTP, secrets de
# client) sont acceptées par le module à cette révision.

mock_provider "keycloak" {}
mock_provider "sops" {}

mock_provider "random" {
  # Un mock tire des chaînes de 4 à 16 caractères ; le module exige au moins
  # 32 caractères pour client_app_secret (chiffrement du vérificateur PKCE) et
  # rejetterait le plan. 48 caractères, comme la longueur demandée.
  mock_resource "random_password" {
    defaults = {
      result = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUV"
    }
  }
}

# ansible/secrets.sops.yaml : mot de passe du bootstrap admin du conteneur
# Keycloak (KC_BOOTSTRAP_ADMIN_PASSWORD), lu au même endroit que le rôle.
override_data {
  target = data.sops_file.ansible
  values = {
    data = {
      demo_planning_kc_keycloak_admin_password = "fake-admin-password"
    }
  }
}

override_module {
  target = module.realm
  outputs = {
    oidc_client_secret              = "fake-app-secret"
    oidc_provisioning_client_secret = "fake-provisioning-secret"
    reste_a_faire                   = ["Les PERSONNES du personnel : ansible/keycloak-planning.yml."]
  }
}

run "trois_secrets_de_client" {
  command = plan

  assert {
    condition     = toset(keys(random_password.client)) == toset(["app", "provisioning", "mcp"])
    error_message = "Un secret par client du realm : app, provisioning et mcp, ni plus ni moins."
  }

  # Le module refuse un client_app_secret de moins de 32 caractères.
  assert {
    condition     = alltrue([for name, password in random_password.client : password.length >= 32])
    error_message = "Les secrets de client doivent faire au moins 32 caractères (exigence du module pour client_app_secret)."
  }

  assert {
    condition     = alltrue([for name, password in random_password.client : password.length == 48 && password.special == false])
    error_message = "Les secrets de client sont tirés sur 48 caractères alphanumériques (pas de caractères spéciaux à échapper dans sops ni dans .env)."
  }
}

# flip.yml attend ces deux valeurs dans ansible/secrets.sops.yaml
# (demo_planning_kc_oidc_client_secret et
# demo_planning_kc_oidc_provisioning_client_secret), recopiées par
# `tofu output -raw` : une sortie inversée pose le mauvais secret.
run "sorties_recopiees_dans_sops" {
  command = plan

  assert {
    condition     = output.oidc_client_secret == "fake-app-secret"
    error_message = "oidc_client_secret doit être la sortie oidc_client_secret du module (client de l'application web)."
  }

  assert {
    condition     = output.oidc_provisioning_client_secret == "fake-provisioning-secret"
    error_message = "oidc_provisioning_client_secret doit être la sortie oidc_provisioning_client_secret du module (compte de service)."
  }

  assert {
    condition     = issensitive(output.oidc_client_secret) && issensitive(output.oidc_provisioning_client_secret)
    error_message = "Les deux secrets de client doivent rester des sorties sensibles."
  }
}
