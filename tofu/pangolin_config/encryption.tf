# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.pangolin_config_state_passphrase) : il contient des secrets
# (PIN, jetons Telegram et ntfy, clé Anthropic, identifiants Newt et OLM, jetons
# d'accès Pangolin). Passphrase DÉDIÉE, distincte de celle des autres states :
# Ansible et la CI la lisent (`tofu output -json`, clé `tofu_state_passphrase`
# de secrets/ansible.sops.yaml), pas l'autre (audit sc1).
#
# Migration en deux temps (audit sc1, phase 2) : la méthode `unencrypted` en
# repli (state et plan) laisse tout marcher, que le state soit encore en clair
# ou déjà chiffré. La prochaine écriture le chiffre. Une PR suivante retire les
# replis : un state en clair est alors refusé.
terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.pangolin_config_state_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    # Retirée avec les replis ci-dessous une fois le state chiffré.
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
