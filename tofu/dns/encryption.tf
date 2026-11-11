# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : terraform_remote_state.pangolin
# y range toutes les sorties de tofu/pangolin, dont le mot de passe de la
# Storage Box. Il déchiffre aussi le state de tofu/pangolin, que ce data
# source lit (remote_state_data_sources), avec la même passphrase.
#
# Migration : le fallback lit l'ancien state en clair ; le premier apply le
# réécrit chiffré. Après cet apply, retirer method "unencrypted" et les deux
# blocs fallback pour refuser tout state en clair.
terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.state
      fallback {
        method = method.unencrypted.migrate
      }
    }

    plan {
      method = method.aes_gcm.state
      fallback {
        method = method.unencrypted.migrate
      }
    }

    remote_state_data_sources {
      remote_state_data_source "pangolin" {
        method = method.aes_gcm.state
      }
    }
  }
}
