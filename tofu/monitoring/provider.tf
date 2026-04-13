terraform {
  required_providers {
    uptimekuma = {
      source  = "breml/uptimekuma"
      version = "~> 0.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4.0"
    }
  }
}

provider "uptimekuma" {
}

provider "sops" {}
