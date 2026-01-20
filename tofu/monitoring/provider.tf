terraform {
  required_providers {
    uptimekuma = {
      source  = "breml/uptimekuma"
      version = "~> 0.1.5"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3.0"
    }
  }
}

provider "uptimekuma" {
}

provider "sops" {}
