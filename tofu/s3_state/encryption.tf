# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (clés S3 des utilisateurs tf_state et ansible_state_reader). Le state de tofu/pangolin_config reste en clair, Ansible le lit sur S3.
#
# Migration : le fallback lit l'ancien state en clair ; le premier apply le
# réécrit chiffré. Une fois chaque module migré, retirer les blocs fallback
# et method "unencrypted" pour refuser tout state en clair.
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
  }
}
