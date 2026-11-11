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

    # Retirée avec les replis ci-dessous une fois le state chiffré.
    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.pangolin_config
      fallback {
        method = method.unencrypted.migrate
      }
    }

    plan {
      method = method.aes_gcm.pangolin_config
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
