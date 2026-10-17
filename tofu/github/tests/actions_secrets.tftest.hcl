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
      uptime_restore_test_urls = {
        betisier = "https://uptime.example.test/api/push/restore-betisier"
        searxng  = "https://uptime.example.test/api/push/restore-searxng"
      }
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
    condition     = github_actions_secret.sops_age_key.secret_name == "SOPS_AGE_KEY"
    error_message = "deploy-docker-app.yaml lit secrets.SOPS_AGE_KEY : le nom du secret de la clé Age a changé."
  }

  assert {
    condition     = github_actions_secret.ssh_private_key.secret_name == "SSH_PRIVATE_KEY"
    error_message = "deploy-docker-app.yaml lit secrets.SSH_PRIVATE_KEY : le nom du secret de la clé de déploiement a changé."
  }

  assert {
    condition     = github_actions_secret.olm_id.secret_name == "OLM_ID"
    error_message = "deploy-docker-app.yaml et ping.yaml lisent secrets.OLM_ID : le nom du secret a changé."
  }

  assert {
    condition     = github_actions_secret.olm_secret.secret_name == "OLM_SECRET"
    error_message = "deploy-docker-app.yaml et ping.yaml lisent secrets.OLM_SECRET : le nom du secret a changé."
  }
}

run "secrets_poses_sur_le_depot_homelab" {
  command = plan

  assert {
    condition = alltrue([
      github_actions_secret.sops_age_key.repository == "homelab",
      github_actions_secret.ssh_private_key.repository == "homelab",
      github_actions_secret.olm_id.repository == "homelab",
      github_actions_secret.olm_secret.repository == "homelab",
    ])
    error_message = "Les quatre secrets Actions doivent être posés sur le dépôt homelab (var.github_repository), celui dont les workflows les lisent."
  }
}

run "valeurs_tirees_de_la_bonne_source" {
  command = plan

  assert {
    condition     = github_actions_secret.sops_age_key.value == "AGE-SECRET-KEY-1FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE"
    error_message = "SOPS_AGE_KEY doit être github_actions_sops_age_key d'ansible/secrets.sops.yaml."
  }

  assert {
    condition     = github_actions_secret.olm_id.value == "fake-olm-id"
    error_message = "OLM_ID doit être la sortie ci_olm_id de l'état pangolin_config."
  }

  assert {
    condition     = github_actions_secret.olm_secret.value == "fake-olm-secret"
    error_message = "OLM_SECRET doit être la sortie ci_olm_secret de l'état pangolin_config (pas ci_olm_id : identifiant et secret inversés)."
  }

  assert {
    condition     = github_actions_secret.ssh_private_key.value == tls_private_key.ci_deploy.private_key_openssh
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
# clé du sous-compte en lecture seule, jamais avec celle du compte principal.
run "restore_test_secrets" {
  command = plan

  assert {
    condition     = github_actions_secret.restore_test_ssh_key.secret_name == "RESTORE_TEST_SSH_KEY" && github_actions_secret.restore_test_storage_box.secret_name == "RESTORE_TEST_STORAGE_BOX" && github_actions_secret.restore_test_push_urls.secret_name == "RESTORE_TEST_PUSH_URLS"
    error_message = "restore-test.yaml lit RESTORE_TEST_SSH_KEY, RESTORE_TEST_STORAGE_BOX et RESTORE_TEST_PUSH_URLS : un nom de secret a changé."
  }

  assert {
    condition     = github_actions_secret.restore_test_ssh_key.value == "fake-restore-test-key"
    error_message = "La clé de la CI doit être celle du sous-compte restore_test de tofu/pangolin."
  }

  assert {
    condition     = github_actions_secret.restore_test_storage_box.value == "u000000-sub1@u000000-sub1.your-storagebox.de"
    error_message = "RESTORE_TEST_STORAGE_BOX doit valoir <utilisateur>@<serveur> du sous-compte."
  }

  assert {
    condition     = jsondecode(github_actions_secret.restore_test_push_urls.value).searxng == "https://uptime.example.test/api/push/restore-searxng"
    error_message = "RESTORE_TEST_PUSH_URLS doit être la map JSON app => URL de uptime_restore_test_urls."
  }

  # Les secrets utilisés par le workflow doivent être ceux déclarés ici.
  assert {
    condition = alltrue([
      for name in ["RESTORE_TEST_SSH_KEY", "RESTORE_TEST_STORAGE_BOX", "RESTORE_TEST_PUSH_URLS", "SOPS_AGE_KEY"] :
      strcontains(file("${path.module}/../../.github/workflows/restore-test.yaml"), "secrets.${name}")
    ])
    error_message = "restore-test.yaml doit lire ses secrets sous les noms déclarés par tofu/github."
  }
}
