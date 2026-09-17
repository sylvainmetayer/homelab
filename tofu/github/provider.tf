terraform {
  required_version = ">= 1.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    # Lit l'immutabilité des releases via la CLI gh, faute de ressource dans
    # integrations/github 6.x - voir repository_planning_equipes.tf.
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
  }
}

# Authenticates via the GITHUB_TOKEN/GH_TOKEN environment variable, e.g.
# export GITHUB_TOKEN="$(gh auth token)"
provider "github" {
  owner = var.github_owner
}
