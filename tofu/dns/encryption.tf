# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : terraform_remote_state.pangolin
# y range toutes les sorties de tofu/pangolin, dont le mot de passe de la
# Storage Box. Il déchiffre aussi le state de tofu/pangolin, que ce data
# source lit (remote_state_data_sources), avec la même passphrase.
#
# Sans fallback : un state en clair (ou chiffré avec une autre clé) est
# refusé. Migré le 11/11/2026.
terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method = method.aes_gcm.state
    }

    plan {
      method = method.aes_gcm.state
    }

    remote_state_data_sources {
      remote_state_data_source "pangolin" {
        method = method.aes_gcm.state
      }
    }
  }
}
