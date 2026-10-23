# Lecture du state chiffré de tofu/pangolin (terraform_remote_state.pangolin,
# remote_state.tf) : même passphrase que son encryption.tf. Le state de ce
# module, lui, reste en clair (aucun bloc state) : Ansible le lit sur S3.
terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    remote_state_data_sources {
      remote_state_data_source "pangolin" {
        method = method.aes_gcm.state
      }
    }
  }
}
