# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (mot de passe et identifiants de la Storage Box et de ses sous-comptes, mots de passe des serveurs). Le state de tofu/pangolin_config reste en clair, Ansible le lit sur S3.
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
  }
}
