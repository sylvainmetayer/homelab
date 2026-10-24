# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.state_encryption_passphrase) : il contient des secrets
# (clés S3 du writer et de l'admin du bucket), chiffré dès sa création.
#
# Sans fallback : un state en clair (ou chiffré avec une autre clé) est
# refusé.
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
