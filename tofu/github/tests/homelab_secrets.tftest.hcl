# Dépôt privé homelab-secrets (ADR 0018), sa clé de déploiement et le secret
# Actions que lisent les workflows de homelab.
#
# Uniquement des `command = plan` : github_repository.homelab_secrets (comme
# les autres dépôts) a prevent_destroy, que le destroy de fin de fichier de
# `tofu test` heurterait, et terraform_data.planning_equipes_immutable_releases
# porte un provisioner local-exec.

# Passphrase factice du chiffrement du state (encryption.tf).
variables {
  state_encryption_passphrase = "tofu-test-passphrase-not-a-secret"
}

mock_provider "github" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "external" {}
mock_provider "sops" {}

override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      github_actions_sops_age_key = "AGE-SECRET-KEY-1FAKE"
      backup_passphrase           = "fake-backup-passphrase"
      hcloud_readonly_token       = "fake-hcloud-readonly-token"
      ntfy_github_token           = "tk_fakentfygithubtoken0000000"
    }
  }
}

override_data {
  target = data.terraform_remote_state.pangolin_config
  values = {
    outputs = {
      ci_olm_id                    = "fake-olm-id"
      ci_olm_secret                = "fake-olm-secret"
      uptime_restore_test_url      = "https://uptime.example.test/api/push/restore-test"
      uptime_storage_box_quota_url = "https://uptime.example.test/api/push/storage-box-quota"
      uptime_secrets_rotation_url  = "https://uptime.example.test/api/push/secrets-rotation"
    }
  }
}

override_data {
  target = data.terraform_remote_state.pangolin
  values = {
    outputs = {
      storage_box_restore_test_username        = "u000000-sub1"
      storage_box_restore_test_server          = "u000000-sub1.your-storagebox.de"
      storage_box_restore_test_ssh_private_key = "fake-restore-test-key"
    }
  }
}

override_data {
  target = data.external.planning_equipes_immutable_releases
  values = {
    result = {
      enabled           = "true"
      enforced_by_owner = "false"
    }
  }
}

# Valeurs propres à cette paire : le mock tls donnerait la même à
# tls_private_key.ci_deploy, et l'assert du câblage ne verrait pas l'échange.
override_resource {
  target = tls_private_key.homelab_secrets_deploy
  values = {
    private_key_openssh = "fake-homelab-secrets-deploy-private-key"
    public_key_openssh  = "ssh-ed25519 FAKEHOMELABSECRETSDEPLOY\n"
  }
}

run "depot_prive_vide" {
  command = plan

  assert {
    condition = (
      github_repository.homelab_secrets.name == "homelab-secrets"
      && github_repository.homelab_secrets.visibility == "private"
      && github_repository.homelab_secrets.auto_init == false
    )
    error_message = "homelab-secrets doit être privé et créé vide (le premier push porte les fichiers copiés de homelab)."
  }

  assert {
    condition     = github_actions_repository_permissions.homelab_secrets.enabled == false
    error_message = "Aucun workflow ne doit tourner dans homelab-secrets : Actions désactivées."
  }
}

run "cle_de_deploiement_en_lecture_seule" {
  command = plan

  assert {
    condition = (
      github_repository_deploy_key.homelab_secrets_ci.read_only == true
      && github_repository_deploy_key.homelab_secrets_ci.repository == "homelab-secrets"
    )
    error_message = "La clé de la CI de homelab ne doit que lire homelab-secrets."
  }

  # Secret du dépôt, pas d'un environnement (lisibles depuis main seulement) :
  # le Lint des PR clone le sous-module avec lui.
  assert {
    condition = (
      github_actions_secret.homelab_secrets_ssh_key.repository == "homelab"
      && github_actions_secret.homelab_secrets_ssh_key.secret_name == "HOMELAB_SECRETS_SSH_KEY"
    )
    error_message = "HOMELAB_SECRETS_SSH_KEY doit être un secret du dépôt homelab, au nom que lisent ses workflows."
  }

  # Le secret et la clé de déploiement viennent de la même paire : une autre
  # clé (ci_deploy, copiée-collée) ferait échouer le clone de la CI.
  assert {
    condition = (
      tls_private_key.homelab_secrets_deploy.algorithm == "ED25519"
      && github_actions_secret.homelab_secrets_ssh_key.value == tls_private_key.homelab_secrets_deploy.private_key_openssh
      && github_repository_deploy_key.homelab_secrets_ci.key == trimspace(tls_private_key.homelab_secrets_deploy.public_key_openssh)
    )
    error_message = "HOMELAB_SECRETS_SSH_KEY doit être la clé privée de tls_private_key.homelab_secrets_deploy (ED25519), dont la publique est la clé de déploiement de homelab-secrets."
  }
}
