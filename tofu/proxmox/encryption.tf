# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (data sops_file y range tout secrets.sops.yaml). Même schéma que tofu/pangolin.
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
  }
}
