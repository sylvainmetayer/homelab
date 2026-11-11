# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (clé privée SSH de déploiement de la CI, clé age de la CI, identifiants OLM).
#
# Sans fallback : un state en clair (ou chiffré avec une autre clé) est
# refusé. Migré le 23/10/2026.
terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    # Passphrase DÉDIÉE du state de tofu/pangolin_config (audit sc1), lu par
    # terraform_remote_state.pangolin_config. Le repli `unencrypted` sert tant
    # que ce state peut être en clair (migration) ; retiré avec celui de
    # tofu/pangolin_config.
    key_provider "pbkdf2" "pangolin_config" {
      passphrase = var.pangolin_config_state_passphrase
    }

    method "aes_gcm" "pangolin_config" {
      keys = key_provider.pbkdf2.pangolin_config
    }

    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.state
    }

    plan {
      method = method.aes_gcm.state
    }

    # States de tofu/pangolin (environments.tf, test de restauration), chiffré
    # avec la même passphrase, et de tofu/pangolin_config, avec la sienne.
    remote_state_data_sources {
      remote_state_data_source "pangolin" {
        method = method.aes_gcm.state
      }
      remote_state_data_source "pangolin_config" {
        method = method.aes_gcm.pangolin_config
        fallback {
          method = method.unencrypted.migrate
        }
      }
    }
  }
}
