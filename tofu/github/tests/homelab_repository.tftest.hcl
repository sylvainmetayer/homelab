# Réglages du dépôt homelab (repository_homelab.tf) : le test fige l'état réel
# relevé le 11/11/2026, pour qu'un changement involontaire se voie en PR.
#
# Uniquement des `command = plan` : github_repository.homelab (comme les autres
# dépôts) a prevent_destroy, que le destroy de fin de fichier de `tofu test`
# heurterait.

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

run "depot_public_en_rebase_seul" {
  command = plan

  assert {
    condition = (
      github_repository.homelab.name == "homelab"
      && github_repository.homelab.visibility == "public"
      && github_repository.homelab.archive_on_destroy == true
    )
    error_message = "homelab est public et un destroy l'archive au lieu de le supprimer."
  }

  assert {
    condition = (
      github_repository.homelab.allow_rebase_merge == true
      && github_repository.homelab.allow_squash_merge == false
      && github_repository.homelab.allow_merge_commit == false
      && github_repository.homelab.delete_branch_on_merge == true
    )
    error_message = "homelab ne fusionne qu'en rebase (squash et merge commit désactivés), branche supprimée après fusion."
  }

  assert {
    condition = (
      github_repository.homelab.security_and_analysis[0].secret_scanning[0].status == "enabled"
      && github_repository.homelab.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    )
    error_message = "Scan de secrets et protection à la poussée doivent rester activés sur homelab."
  }
}

run "actions_en_lecture_seule" {
  command = plan

  assert {
    condition = (
      github_workflow_repository_permissions.homelab.default_workflow_permissions == "read"
      && github_workflow_repository_permissions.homelab.can_approve_pull_request_reviews == false
    )
    error_message = "Le GITHUB_TOKEN par défaut de homelab doit rester en lecture seule, sans droit d'approbation."
  }

  assert {
    condition = (
      github_actions_repository_permissions.homelab.enabled == true
      && github_actions_repository_permissions.homelab.allowed_actions == "all"
    )
    error_message = "Actions reste activé sur homelab, toutes actions permises."
  }

  assert {
    condition = (
      github_repository_vulnerability_alerts.homelab.enabled == false
      && github_repository_dependabot_security_updates.homelab.enabled == false
    )
    error_message = "Alertes et mises à jour Dependabot sont désactivées sur homelab (état réel au 11/11)."
  }
}
