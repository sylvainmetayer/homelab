# Secrets Actions du dépôt homelab : ce que les workflows de .github/ lisent
# (deploy-docker-app.yaml, ping.yaml) doit sortir de la bonne source, sous le
# bon nom. Un nom de secret faux ne casse rien au plan : c'est le déploiement
# suivant qui échoue, sur un `secrets.X` vide.
#
# Uniquement des `command = plan` : terraform_data.planning_equipes_immutable_releases
# porte un provisioner local-exec (`gh api --method PUT`) qui s'exécuterait
# à l'apply, et github_repository.planning_equipes a prevent_destroy, que le
# destroy de fin de fichier de `tofu test` heurterait.

# data.github_user.owner (environments.tf) : un id numérique, comme celui que
# reviewers.users attend.
# Passphrase factice du chiffrement du state (encryption.tf).
variables {
  state_encryption_passphrase = "tofu-test-passphrase-not-a-secret"
}

mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id = "8873695"
    }
  }
}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "external" {}
mock_provider "sops" {}

# ansible/secrets.sops.yaml : seule la clé Age du destinataire github-actions
# est lue ici (secrets.tf).
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      github_actions_sops_age_key = "AGE-SECRET-KEY-1FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE"
      backup_passphrase           = "fake-backup-passphrase"
      hcloud_readonly_token       = "fake-hcloud-readonly-token"
    }
  }
}

# Sorties de tofu/pangolin_config (private_resources.tf, pangolin_client.ci_runner),
# lues dans l'état S3 : aucun backend n'est joignable en test.
override_data {
  target = data.terraform_remote_state.pangolin_config
  values = {
    outputs = {
      ci_olm_id     = "fake-olm-id"
      ci_olm_secret = "fake-olm-secret"
      # restore_test_monitor.tf
      uptime_restore_test_url = "https://uptime.example.test/api/push/restore-test"
      # storage_box_quota_monitor.tf
      uptime_storage_box_quota_url = "https://uptime.example.test/api/push/storage-box-quota"
    }
  }
}

# Sorties de tofu/pangolin (storage_box.tf, sous-compte en lecture seule du
# test de restauration), lues dans l'état S3.
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

# Lecture `gh api …/immutable-releases` : repoussée à l'apply par son
# depends_on, jamais lue en plan. Surchargée quand même pour qu'aucun test
# n'appelle `gh`.
override_data {
  target = data.external.planning_equipes_immutable_releases
  values = {
    result = {
      enabled           = "true"
      enforced_by_owner = "false"
    }
  }
}

run "noms_des_secrets_lus_par_les_workflows" {
  command = plan

  assert {
    condition     = github_actions_environment_secret.sops_age_key.secret_name == "SOPS_AGE_KEY"
    error_message = "deploy-docker-app.yaml lit secrets.SOPS_AGE_KEY : le nom du secret de la clé Age a changé."
  }

  assert {
    condition     = github_actions_environment_secret.ssh_private_key.secret_name == "SSH_PRIVATE_KEY"
    error_message = "deploy-docker-app.yaml lit secrets.SSH_PRIVATE_KEY : le nom du secret de la clé de déploiement a changé."
  }

  assert {
    condition     = github_actions_environment_secret.olm_id.secret_name == "OLM_ID"
    error_message = "deploy-docker-app.yaml et ping.yaml lisent secrets.OLM_ID : le nom du secret a changé."
  }

  assert {
    condition     = github_actions_environment_secret.olm_secret.secret_name == "OLM_SECRET"
    error_message = "deploy-docker-app.yaml et ping.yaml lisent secrets.OLM_SECRET : le nom du secret a changé."
  }
}

run "secrets_poses_sur_le_depot_homelab" {
  command = plan

  assert {
    condition = alltrue([
      github_actions_environment_secret.sops_age_key.repository == "homelab",
      github_actions_environment_secret.ssh_private_key.repository == "homelab",
      github_actions_environment_secret.olm_id.repository == "homelab",
      github_actions_environment_secret.olm_secret.repository == "homelab",
    ])
    error_message = "Les quatre secrets Actions doivent être posés sur le dépôt homelab (var.github_repository), celui dont les workflows les lisent."
  }

  assert {
    condition = alltrue([
      for s in [github_actions_environment_secret.sops_age_key, github_actions_environment_secret.ssh_private_key, github_actions_environment_secret.olm_id, github_actions_environment_secret.olm_secret] :
      s.environment == "production"
    ])
    error_message = "Les secrets de déploiement vivent dans l'environnement production, lisible depuis main seulement."
  }

  assert {
    condition     = github_repository_environment.production.deployment_branch_policy[0].custom_branch_policies && github_repository_environment_deployment_policy.production_main.branch_pattern == "main"
    error_message = "L'environnement production n'accepte que la branche main."
  }

  # Un job qui lit ces secrets sans `environment: production` reçoit des
  # valeurs vides : chaque workflow qui les cite doit le déclarer.
  assert {
    condition = alltrue([
      for f in ["deploy-docker-app.yaml", "ping.yaml"] :
      strcontains(file("${path.module}/../../.github/workflows/${f}"), "environment: production")
    ])
    error_message = "deploy-docker-app.yaml et ping.yaml doivent déclarer environment: production."
  }
}

run "ruleset_de_main" {
  command = plan

  assert {
    condition     = toset([for c in github_repository_ruleset.homelab_main.rules[0].required_status_checks[0].required_check : c.context]) == toset(["Ansible lint", "OpenTofu lint", "CI lint", "Tests"])
    error_message = "main exige Ansible lint, OpenTofu lint, CI lint et Tests."
  }

  # Un check requis dont le job a changé de nom n'arrive jamais : toutes les
  # PR resteraient bloquées.
  assert {
    condition = alltrue([
      strcontains(file("${path.module}/../../.github/workflows/lint.yaml"), "name: Ansible lint"),
      strcontains(file("${path.module}/../../.github/workflows/lint.yaml"), "name: OpenTofu lint"),
      strcontains(file("${path.module}/../../.github/workflows/lint.yaml"), "name: CI lint"),
      strcontains(file("${path.module}/../../.github/workflows/test.yaml"), "name: Tests\n"),
    ])
    error_message = "Les checks requis par le ruleset doivent rester les noms des jobs de lint.yaml et test.yaml."
  }

  assert {
    condition     = github_repository_ruleset.homelab_main.rules[0].non_fast_forward && github_repository_ruleset.homelab_main.rules[0].deletion
    error_message = "main refuse le force-push et la suppression."
  }

  # Interrupteur à false par défaut : tant que le dépôt fusionne en rebase,
  # exiger des signatures bloquerait toutes les PR.
  assert {
    condition     = length(github_repository_ruleset.homelab_main_signed_commits) == 0
    error_message = "Le ruleset des commits signés n'existe que si homelab_require_signed_commits vaut true."
  }
}

run "commits_signes_sur_main" {
  command = plan

  variables {
    homelab_require_signed_commits = true
  }

  override_data {
    target = data.github_repository.homelab
    values = {
      allow_rebase_merge = false
      allow_squash_merge = true
      allow_merge_commit = false
    }
  }

  assert {
    condition     = github_repository_ruleset.homelab_main_signed_commits[0].rules[0].required_signatures
    error_message = "main exige des commits signés."
  }

  # Un bypass couvre toutes les règles de son ruleset : le push direct de
  # l'admin passerait non signé.
  assert {
    condition     = length(github_repository_ruleset.homelab_main_signed_commits[0].bypass_actors) == 0
    error_message = "Le ruleset des commits signés ne doit avoir aucun bypass_actors."
  }

  assert {
    condition     = github_repository_ruleset.homelab_main_signed_commits[0].enforcement == "active" && github_repository_ruleset.homelab_main_signed_commits[0].conditions[0].ref_name[0].include == tolist(["~DEFAULT_BRANCH"])
    error_message = "Le ruleset des commits signés vise la branche par défaut, en mode actif."
  }
}

# GitHub ne signe pas les commits d'un « Rebase and merge » : activer la règle
# tant que le rebase est permis bloquerait toutes les PR, Renovate compris.
run "commits_signes_refuses_avec_le_rebase" {
  command = plan

  variables {
    homelab_require_signed_commits = true
  }

  override_data {
    target = data.github_repository.homelab
    values = {
      allow_rebase_merge = true
      allow_squash_merge = true
      allow_merge_commit = false
    }
  }

  expect_failures = [github_repository_ruleset.homelab_main_signed_commits]
}

run "valeurs_tirees_de_la_bonne_source" {
  command = plan

  assert {
    condition     = github_actions_environment_secret.sops_age_key.value == "AGE-SECRET-KEY-1FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE"
    error_message = "SOPS_AGE_KEY doit être github_actions_sops_age_key d'ansible/secrets.sops.yaml."
  }

  assert {
    condition     = github_actions_environment_secret.olm_id.value == "fake-olm-id"
    error_message = "OLM_ID doit être la sortie ci_olm_id de l'état pangolin_config."
  }

  assert {
    condition     = github_actions_environment_secret.olm_secret.value == "fake-olm-secret"
    error_message = "OLM_SECRET doit être la sortie ci_olm_secret de l'état pangolin_config (pas ci_olm_id : identifiant et secret inversés)."
  }

  assert {
    condition     = github_actions_environment_secret.ssh_private_key.value == tls_private_key.ci_deploy.private_key_openssh
    error_message = "SSH_PRIVATE_KEY doit être la clé privée OpenSSH de tls_private_key.ci_deploy, celle dont la publique est dans keys/github-actions.pub."
  }
}

run "cle_de_deploiement_ci" {
  command = plan

  assert {
    condition     = tls_private_key.ci_deploy.algorithm == "ED25519"
    error_message = "La clé de déploiement CI doit rester en ED25519."
  }

  # 00-setup.yaml pousse keys/*.pub dans authorized_keys : le fichier doit
  # être à cet endroit, lisible, et porter le commentaire github-actions.
  assert {
    condition     = endswith(local_file.ci_deploy_public_key.filename, "/../../keys/github-actions.pub")
    error_message = "La clé publique CI doit être écrite dans keys/github-actions.pub à la racine du dépôt (lue par ansible/00-setup.yaml)."
  }

  assert {
    condition     = local_file.ci_deploy_public_key.file_permission == "0644"
    error_message = "keys/github-actions.pub doit être en 0644."
  }

  assert {
    condition     = local_file.ci_deploy_public_key.content == "${trimspace(tls_private_key.ci_deploy.public_key_openssh)} github-actions\n"
    error_message = "keys/github-actions.pub doit contenir la clé publique de tls_private_key.ci_deploy suivie du commentaire « github-actions » et d'un saut de ligne."
  }

  assert {
    condition     = output.ci_deploy_public_key == tls_private_key.ci_deploy.public_key_openssh
    error_message = "La sortie ci_deploy_public_key doit être la clé publique OpenSSH de la clé de déploiement."
  }
}

# path-bypass-review.yaml attend l'approbation de cet environnement : un nom
# différent créerait à la volée un environnement sans relecteur, et le job
# passerait sans attendre.
run "environnement_de_relecture_des_chemins_publics" {
  command = plan

  assert {
    condition     = length(regexall("environment: ${github_repository_environment.relecture_chemins_publics.environment}\\n", file("${path.module}/../../.github/workflows/path-bypass-review.yaml"))) == 1
    error_message = "path-bypass-review.yaml doit attendre l'environnement que pose environments.tf."
  }

  assert {
    condition     = github_repository_environment.relecture_chemins_publics.repository == "homelab"
    error_message = "L'environnement de relecture doit être posé sur le dépôt homelab."
  }

  assert {
    condition     = contains(github_repository_environment.relecture_chemins_publics.reviewers[0].users, 8873695)
    error_message = "Le propriétaire du dépôt doit être relecteur obligatoire de l'environnement."
  }
}

# .github/workflows/restore-test.yaml : la CI ne lit la Storage Box qu'avec la
# clé du sous-compte en lecture seule, et son environnement ne porte que ses
# propres secrets (ni la clé age, ni la clé de déploiement).
run "restore_test_secrets" {
  command = plan

  assert {
    condition = alltrue([
      for s in [
        github_actions_environment_secret.restore_test_ssh_key,
        github_actions_environment_secret.restore_test_storage_box,
        github_actions_environment_secret.restore_test_borg_passphrase,
        github_actions_environment_secret.restore_test_push_url,
      ] : s.environment == "restore-test" && s.repository == "homelab"
    ])
    error_message = "Les secrets du test de restauration doivent être dans l'environnement restore-test du dépôt homelab."
  }

  assert {
    condition     = github_repository_environment.restore_test.deployment_branch_policy[0].custom_branch_policies && github_repository_environment_deployment_policy.restore_test_main.branch_pattern == "main"
    error_message = "L'environnement restore-test ne doit être lisible que depuis main."
  }

  assert {
    condition     = github_actions_environment_secret.restore_test_ssh_key.value == "fake-restore-test-key"
    error_message = "La clé de la CI doit être celle du sous-compte restore_test de tofu/pangolin."
  }

  assert {
    condition     = github_actions_environment_secret.restore_test_storage_box.value == "u000000-sub1@u000000-sub1.your-storagebox.de"
    error_message = "RESTORE_TEST_STORAGE_BOX doit valoir <utilisateur>@<serveur> du sous-compte."
  }

  assert {
    condition     = github_actions_environment_secret.restore_test_borg_passphrase.value == "fake-backup-passphrase"
    error_message = "RESTORE_TEST_BORG_PASSPHRASE doit être backup_passphrase d'ansible/secrets.sops.yaml."
  }

  assert {
    condition     = github_actions_environment_secret.restore_test_push_url.value == "https://uptime.example.test/api/push/restore-test"
    error_message = "RESTORE_TEST_PUSH_URL doit être l'output uptime_restore_test_url de tofu/pangolin_config."
  }

  # Le workflow lit ces secrets sous ces noms, dans cet environnement.
  assert {
    condition = alltrue([
      for name in ["RESTORE_TEST_SSH_KEY", "RESTORE_TEST_STORAGE_BOX", "RESTORE_TEST_BORG_PASSPHRASE", "RESTORE_TEST_PUSH_URL"] :
      strcontains(file("${path.module}/../../.github/workflows/restore-test.yaml"), "secrets.${name}")
    ])
    error_message = "restore-test.yaml doit lire ses secrets sous les noms déclarés par tofu/github."
  }

  assert {
    condition     = length(regexall("environment: restore-test\\n", file("${path.module}/../../.github/workflows/restore-test.yaml"))) == 2
    error_message = "Les jobs restore et report de restore-test.yaml doivent déclarer environment: restore-test."
  }

  assert {
    condition     = !strcontains(file("${path.module}/../../.github/workflows/restore-test.yaml"), "SOPS_AGE_KEY")
    error_message = "restore-test.yaml ne doit pas lire la clé age : la passphrase borg lui suffit."
  }
}

# .github/workflows/storage-box-quota.yaml : un jeton Hetzner en lecture seule
# et l'URL push de son moniteur, dans un environnement à lui, lisible depuis
# main seulement.
run "storage_box_quota_secrets" {
  command = plan

  assert {
    condition = alltrue([
      for s in [
        github_actions_environment_secret.storage_box_quota_hcloud_token,
        github_actions_environment_secret.storage_box_quota_push_url,
      ] : s.environment == "storage-box-quota" && s.repository == "homelab"
    ])
    error_message = "Les secrets du contrôle de la Storage Box doivent être dans l'environnement storage-box-quota du dépôt homelab."
  }

  assert {
    condition     = github_repository_environment.storage_box_quota.deployment_branch_policy[0].custom_branch_policies && github_repository_environment_deployment_policy.storage_box_quota_main.branch_pattern == "main"
    error_message = "L'environnement storage-box-quota ne doit être lisible que depuis main."
  }

  assert {
    condition     = github_actions_environment_secret.storage_box_quota_hcloud_token.value == "fake-hcloud-readonly-token"
    error_message = "STORAGE_BOX_QUOTA_HCLOUD_TOKEN doit être hcloud_readonly_token d'ansible/secrets.sops.yaml (jeton en lecture seule), jamais HCLOUD_TOKEN."
  }

  assert {
    condition     = github_actions_environment_secret.storage_box_quota_push_url.value == "https://uptime.example.test/api/push/storage-box-quota"
    error_message = "STORAGE_BOX_QUOTA_PUSH_URL doit être l'output uptime_storage_box_quota_url de tofu/pangolin_config."
  }

  assert {
    condition = alltrue([
      for name in ["STORAGE_BOX_QUOTA_HCLOUD_TOKEN", "STORAGE_BOX_QUOTA_PUSH_URL"] :
      strcontains(file("${path.module}/../../.github/workflows/storage-box-quota.yaml"), "secrets.${name}")
    ]) && strcontains(file("${path.module}/../../.github/workflows/storage-box-quota.yaml"), "environment: storage-box-quota\n")
    error_message = "storage-box-quota.yaml doit lire ses secrets sous les noms déclarés par tofu/github, dans l'environnement storage-box-quota."
  }
}
