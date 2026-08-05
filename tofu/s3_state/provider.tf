terraform {
  required_version = ">= 1.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "< 3.0.0"
    }
  }
}

provider "ovh" {
  endpoint = "ovh-eu"
}
