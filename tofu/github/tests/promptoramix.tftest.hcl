# Dépôt promptoramix (IA du tournoi Linkx) et protection de son main.
#
# Uniquement des `command = plan` : github_repository.promptoramix (comme
# planning_equipes) a prevent_destroy, que le destroy de fin de fichier de
# `tofu test` heurterait, et terraform_data.planning_equipes_immutable_releases
# porte un provisioner local-exec.

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

override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      github_actions_sops_age_key = "AGE-SECRET-KEY-1FAKE"
    }
  }
}

override_data {
  target = data.terraform_remote_state.pangolin_config
  values = {
    outputs = {
      ci_olm_id     = "fake-olm-id"
      ci_olm_secret = "fake-olm-secret"
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

run "depot_public_cree_vide" {
  command = plan

  # Le nom est celui de l'image que déploie ansible/roles/promptoramix
  # (ghcr.io/sylvainmetayer/promptoramix) : le paquet GHCR porte le nom du
  # dépôt qui le publie.
  assert {
    condition = (
      github_repository.promptoramix.name == "promptoramix"
      && length(regexall("image: ghcr\\.io/sylvainmetayer/${github_repository.promptoramix.name}:main(@|\\s)", file("${path.module}/../../ansible/roles/promptoramix/templates/compose.yaml"))) == 1
    )
    error_message = "Le dépôt doit s'appeler comme l'image que déploie ansible/roles/promptoramix (ghcr.io/sylvainmetayer/promptoramix:main)."
  }

  assert {
    condition     = github_repository.promptoramix.visibility == "public"
    error_message = "promptoramix est public : flip tire son image sans identifiants."
  }

  # L'historique existant arrive par une poussée : un README auto-généré en
  # ferait un force-push sur une racine étrangère.
  assert {
    condition     = github_repository.promptoramix.auto_init == false
    error_message = "auto_init doit rester à false : le dépôt est créé vide pour recevoir l'historique existant."
  }

  assert {
    condition     = github_repository.promptoramix.archive_on_destroy == true
    error_message = "archive_on_destroy doit rester à true : un destroy archive le dépôt au lieu de le supprimer."
  }

  assert {
    condition     = toset(github_repository.promptoramix.topics) == toset(["rust", "linkx", "game-ai", "marmelab"])
    error_message = "Les sujets du dépôt (rust, linkx, game-ai, marmelab) ont changé."
  }

  assert {
    condition = (
      github_repository.promptoramix.security_and_analysis[0].secret_scanning[0].status == "enabled"
      && github_repository.promptoramix.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    )
    error_message = "Scan de secrets et protection à la poussée doivent être activés sur le dépôt public."
  }
}

run "securite_et_dependances_promptoramix" {
  command = plan

  assert {
    condition     = github_repository_vulnerability_alerts.promptoramix.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur promptoramix."
  }

  assert {
    condition     = github_repository_dependabot_security_updates.promptoramix.enabled == false
    error_message = "Les PR automatiques Dependabot doivent rester désactivées : Renovate porte les montées de version."
  }

  assert {
    condition = (
      github_workflow_repository_permissions.promptoramix.default_workflow_permissions == "read"
      && github_workflow_repository_permissions.promptoramix.can_approve_pull_request_reviews == false
    )
    error_message = "Le GITHUB_TOKEN par défaut de promptoramix doit rester en lecture seule, sans droit d'approbation."
  }
}

run "protection_de_main_promptoramix" {
  command = plan

  assert {
    condition = (
      github_branch_protection.promptoramix_main.pattern == "main"
      && github_branch_protection.promptoramix_main.repository_id == github_repository.promptoramix.node_id
    )
    error_message = "La protection doit porter sur le main de github_repository.promptoramix."
  }

  # false : la première poussée de l'historique et un correctif d'urgence
  # pendant le tournoi passent sans revue.
  assert {
    condition     = github_branch_protection.promptoramix_main.enforce_admins == false
    error_message = "enforce_admins doit rester à false."
  }

  assert {
    condition = (
      length(github_branch_protection.promptoramix_main.required_pull_request_reviews) == 1
      && github_branch_protection.promptoramix_main.required_pull_request_reviews[0].required_approving_review_count == 0
    )
    error_message = "PR obligatoires sur main, sans approbation requise (mainteneur seul)."
  }

  assert {
    condition = (
      github_branch_protection.promptoramix_main.allows_force_pushes == false
      && github_branch_protection.promptoramix_main.allows_deletions == false
      && github_branch_protection.promptoramix_main.require_conversation_resolution == true
    )
    error_message = "Ni force-push ni suppression de main, et conversations résolues avant fusion."
  }
}
