# Chiffrement du state de ce module (OpenTofu, AES-GCM, clé dérivée par
# PBKDF2 de var.pangolin_config_state_passphrase) : il contient des secrets
# (PIN, jetons Telegram et ntfy, clé Anthropic, identifiants Newt et OLM, jetons
# d'accès Pangolin). Passphrase DÉDIÉE, distincte de celle des autres states :
# Ansible et la CI la lisent (`tofu output -json`, clé `tofu_state_passphrase`
# de secrets/ansible.sops.yaml), pas l'autre (audit sc1).
#
# Sans fallback : un state en clair (ou chiffré avec une autre clé) est
# refusé. Migré le 12/11/2026 par un apply -refresh-only.
#
# Nom du key_provider « pangolin_config », pas « state » : le state chiffré
# range le sel PBKDF2 sous l'adresse `key_provider.pbkdf2.<nom>`, et tofu/site
# et tofu/github, qui le déchiffrent, cherchent le sel sous le nom de LEUR
# key_provider (« state » y est déjà pris par leur passphrase commune). Un nom
# différent donne « decryption failed for all provided methods » chez eux
# (essayé le 11/11) ; invariants.tftest.hcl garde les trois noms égaux.
terraform {
  encryption {
    key_provider "pbkdf2" "pangolin_config" {
      passphrase = var.pangolin_config_state_passphrase
    }

    method "aes_gcm" "pangolin_config" {
      keys = key_provider.pbkdf2.pangolin_config
    }

    state {
      method = method.aes_gcm.pangolin_config
    }

    plan {
      method = method.aes_gcm.pangolin_config
    }
  }
}
