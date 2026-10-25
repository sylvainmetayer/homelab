# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (clé privée SSH de déploiement de la CI, clé age de la CI, identifiants OLM). Le state de tofu/pangolin_config reste en clair, Ansible le lit sur S3.
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

    state {
      method = method.aes_gcm.state
    }

    plan {
      method = method.aes_gcm.state
    }

    # State de tofu/pangolin (restore_test_secrets.tf), chiffré avec la même
    # passphrase.
    remote_state_data_sources {
      remote_state_data_source "pangolin" {
        method = method.aes_gcm.state
      }
    }
  }
}
