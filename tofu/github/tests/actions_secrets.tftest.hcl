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
    condition     = toset([for c in github_repository_ruleset.homelab_main.rules[0].required_status_checks[0].required_check : c.context]) == toset(["Ansible lint", "OpenTofu lint", "Tests"])
    error_message = "main exige Ansible lint, OpenTofu lint et Tests."
  }

  # Un check requis dont le job a changé de nom n'arrive jamais : toutes les
  # PR resteraient bloquées.
  assert {
    condition = alltrue([
      strcontains(file("${path.module}/../../.github/workflows/lint.yaml"), "name: Ansible lint"),
      strcontains(file("${path.module}/../../.github/workflows/lint.yaml"), "name: OpenTofu lint"),
      strcontains(file("${path.module}/../../.github/workflows/test.yaml"), "name: Tests\n"),
    ])
    error_message = "Les checks requis par le ruleset doivent rester les noms des jobs de lint.yaml et test.yaml."
  }

  assert {
    condition     = github_repository_ruleset.homelab_main.rules[0].non_fast_forward && github_repository_ruleset.homelab_main.rules[0].deletion
    error_message = "main refuse le force-push et la suppression."
  }
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
