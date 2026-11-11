terraform {
  required_version = ">= 1.0"

  required_providers {
    # Build du fork, pas une version de l'amont : `mise run provider-fork` le pose
    # dans terraform.d/plugins avant `tofu init` (ADR 0021).
    pangolin = {
      source  = "stackopshq/pangolin"
      version = "= 1.7.0-sylvain.5"
    }
    uptimekuma = {
      source  = "breml/uptimekuma"
      version = "~> 0.5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    # Clients OIDC et groupes de Pocket ID (pocket_id.tf, ADR 0030).
    pocketid = {
      source  = "trozz/pocketid"
      version = "= 2.5.0"
    }
  }
}

# Connexion par utilisateur/mot de passe (le 2FA doit rester coupé). L'échec de
# connexion à l'instance PikaPods (breml/terraform-provider-uptimekuma#358, avec
# la 0.3.3) ne se produit plus depuis la 0.4.x, même si l'issue reste ouverte en
# amont. La 0.5.0 lit et écrit l'instance sans écart (plan du 01/11/2026), sauf
# le jeton du canal ntfy, que la 0.4.0 n'envoyait pas (website_ntfy.tf).
provider "uptimekuma" {
  endpoint = local.uptimekuma_endpoint
  username = local.uptimekuma_username
  password = local.uptimekuma_password
}

provider "pangolin" {
  url     = local.pangolin_url
  api_key = local.pangolin_api_key
  org_id  = local.pangolin_org_id
}

# Clé « root » (admin du serveur) : une clé d'organisation ne peut pas créer un
# fournisseur d'identité (403 « Key does not have root access »). Servie à
# pangolin_idp et pangolin_idp_org seulement (pocket_id.tf).
provider "pangolin" {
  alias   = "root"
  url     = local.pangolin_url
  api_key = local.pangolin_root_api_key
  org_id  = local.pangolin_org_id
}

# Clé STATIC_API_KEY de Pocket ID (rôle pocket_id), la même clé SOPS
# pocket_id_static_api_key dans secrets.sops.yaml et ansible.sops.yaml.
provider "pocketid" {
  base_url  = local.pocket_id_issuer
  api_token = local.pocket_id_api_token
}
