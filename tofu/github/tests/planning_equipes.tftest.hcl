# Dépôt planning-equipes et protection de son main (flip-planning#286).
#
# Uniquement des `command = plan` : terraform_data.planning_equipes_immutable_releases
# porte un provisioner local-exec (`gh api --method PUT`) qui s'exécuterait
# à l'apply, et github_repository.planning_equipes a prevent_destroy, que le
# destroy de fin de fichier de `tofu test` heurterait.

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

run "depot_cree_vide" {
  command = plan

  assert {
    condition     = github_repository.planning_equipes.name == "planning-equipes"
    error_message = "Le dépôt doit s'appeler planning-equipes (URL imprimée sur les PDF distribués)."
  }

  # L'historique réécrit (flip-planning#198) arrive par une poussée : un
  # README auto-généré ferait de cette poussée un force-push sur une racine
  # étrangère.
  assert {
    condition     = github_repository.planning_equipes.auto_init == false
    error_message = "auto_init doit rester à false : le dépôt est créé vide pour recevoir l'historique réécrit."
  }

  # Supprimer le dépôt emporterait issues, releases et URL des PDF.
  assert {
    condition     = github_repository.planning_equipes.archive_on_destroy == true
    error_message = "archive_on_destroy doit rester à true : un destroy archive le dépôt au lieu de le supprimer."
  }

  assert {
    condition     = github_repository.planning_equipes.has_issues == true && github_repository.planning_equipes.has_wiki == false
    error_message = "Issues activées, wiki désactivé sur planning-equipes."
  }

  assert {
    condition     = contains(github_repository.planning_equipes.topics, "timefold") && length(github_repository.planning_equipes.topics) == 5
    error_message = "Les cinq sujets du dépôt (planning, scheduling, timefold, quarkus, angular) ont changé."
  }
}

run "options_de_fusion" {
  command = plan

  assert {
    condition     = github_repository.planning_equipes.allow_merge_commit == false
    error_message = "Les merge commits doivent rester désactivés sur planning-equipes."
  }

  assert {
    condition     = github_repository.planning_equipes.allow_squash_merge && github_repository.planning_equipes.allow_rebase_merge
    error_message = "Squash et rebase doivent rester autorisés sur planning-equipes."
  }

  # git-cliff lit les commits conventionnels de main (flip-planning#248) : le
  # titre d'un squash doit être celui de la PR, pas « Merge pull request #n ».
  assert {
    condition     = github_repository.planning_equipes.squash_merge_commit_title == "PR_TITLE"
    error_message = "squash_merge_commit_title doit rester PR_TITLE : git-cliff lit le titre des commits de main."
  }

  assert {
    condition     = github_repository.planning_equipes.squash_merge_commit_message == "COMMIT_MESSAGES"
    error_message = "squash_merge_commit_message doit rester COMMIT_MESSAGES."
  }

  assert {
    condition     = github_repository.planning_equipes.delete_branch_on_merge && github_repository.planning_equipes.allow_auto_merge && github_repository.planning_equipes.allow_update_branch
    error_message = "delete_branch_on_merge, allow_auto_merge et allow_update_branch doivent rester activés."
  }

  # Pendant du check DCO : un commit fait depuis l'interface web est signé.
  assert {
    condition     = github_repository.planning_equipes.web_commit_signoff_required == true
    error_message = "web_commit_signoff_required doit rester à true (pendant du check DCO)."
  }
}

run "securite_et_dependances" {
  command = plan

  assert {
    condition     = github_repository_vulnerability_alerts.planning_equipes.enabled == true
    error_message = "Les alertes Dependabot doivent rester activées sur planning-equipes."
  }

  # Renovate porte les montées de version, avec dependencyDashboardApproval
  # sur les majeures : des PR Dependabot passeraient à côté de ce verrou.
  assert {
    condition     = github_repository_dependabot_security_updates.planning_equipes.enabled == false
    error_message = "Les PR automatiques Dependabot doivent rester désactivées : Renovate porte les montées de version."
  }

  assert {
    condition     = github_workflow_repository_permissions.planning_equipes.default_workflow_permissions == "read"
    error_message = "Le GITHUB_TOKEN par défaut de planning-equipes doit rester en lecture seule."
  }

  assert {
    condition     = github_workflow_repository_permissions.planning_equipes.can_approve_pull_request_reviews == false
    error_message = "Les workflows ne doivent pas pouvoir approuver de PR sur planning-equipes."
  }
}

run "depot_public_avec_scan_de_secrets" {
  command = plan

  variables {
    planning_equipes_visibility = "public"
  }

  assert {
    condition     = github_repository.planning_equipes.visibility == "public"
    error_message = "La visibilité du dépôt doit suivre var.planning_equipes_visibility."
  }

  assert {
    condition     = length(github_repository.planning_equipes.security_and_analysis) == 1
    error_message = "Un dépôt public doit porter le bloc security_and_analysis."
  }

  assert {
    condition     = github_repository.planning_equipes.security_and_analysis[0].secret_scanning[0].status == "enabled"
    error_message = "Le scan de secrets doit être activé sur le dépôt public."
  }

  assert {
    condition     = github_repository.planning_equipes.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    error_message = "La protection à la poussée doit être activée sur le dépôt public."
  }
}

# Sans GitHub Advanced Security, l'API rejette le scan de secrets sur un dépôt
# privé : le bloc doit disparaître avec la visibilité publique.
run "depot_prive_sans_scan_de_secrets" {
  command = plan

  variables {
    planning_equipes_visibility = "private"
  }

  assert {
    condition     = github_repository.planning_equipes.visibility == "private"
    error_message = "La visibilité du dépôt doit suivre var.planning_equipes_visibility."
  }

  assert {
    condition     = length(github_repository.planning_equipes.security_and_analysis) == 0
    error_message = "Un dépôt privé ne doit pas porter security_and_analysis : l'API le rejette sans GitHub Advanced Security."
  }
}

run "visibilite_invalide_rejetee" {
  command = plan

  variables {
    planning_equipes_visibility = "internal"
  }

  expect_failures = [
    var.planning_equipes_visibility,
  ]
}

run "protection_de_main" {
  command = plan

  assert {
    condition     = github_branch_protection.planning_equipes_main.pattern == "main"
    error_message = "La protection doit porter sur main."
  }

  assert {
    condition     = github_branch_protection.planning_equipes_main.repository_id == github_repository.planning_equipes.node_id
    error_message = "La protection doit viser le node_id de github_repository.planning_equipes."
  }

  # false : c'est ce qui laisse pousser l'historique réécrit sur main, et
  # corriger en urgence sans une revue qui ne viendra pas.
  assert {
    condition     = github_branch_protection.planning_equipes_main.enforce_admins == false
    error_message = "enforce_admins doit rester à false (poussée de l'historique réécrit, correctifs d'urgence)."
  }

  assert {
    condition     = length(github_branch_protection.planning_equipes_main.required_pull_request_reviews) == 1
    error_message = "Les PR doivent rester obligatoires sur main."
  }

  # Mainteneur seul : personne d'autre ne peut approuver.
  assert {
    condition     = github_branch_protection.planning_equipes_main.required_pull_request_reviews[0].required_approving_review_count == 0
    error_message = "Zéro approbation requise : un mainteneur seul ne peut pas être approuvé par un autre."
  }

  assert {
    condition     = github_branch_protection.planning_equipes_main.required_pull_request_reviews[0].dismiss_stale_reviews == true
    error_message = "dismiss_stale_reviews doit rester à true."
  }

  assert {
    condition     = github_branch_protection.planning_equipes_main.allows_force_pushes == false && github_branch_protection.planning_equipes_main.allows_deletions == false
    error_message = "Ni force-push ni suppression de main."
  }

  assert {
    condition     = github_branch_protection.planning_equipes_main.require_conversation_resolution == true
    error_message = "Les conversations doivent être résolues avant fusion."
  }
}

# Vide par défaut : un check requis qui ne rapporte jamais laisse toutes les
# PR en attente (dco.yml absent, jobs sautés sur les PR de fork).
run "aucun_check_requis_par_defaut" {
  command = plan

  assert {
    condition     = length(github_branch_protection.planning_equipes_main.required_status_checks) == 0
    error_message = "Sans var.planning_equipes_required_checks, main ne doit exiger aucun check."
  }
}

run "checks_requis_quand_listes" {
  command = plan

  variables {
    planning_equipes_required_checks = ["test", "Certificat d'origine (DCO)"]
  }

  assert {
    condition     = length(github_branch_protection.planning_equipes_main.required_status_checks) == 1
    error_message = "Une liste de checks non vide doit produire un bloc required_status_checks."
  }

  assert {
    condition     = github_branch_protection.planning_equipes_main.required_status_checks[0].strict == true
    error_message = "Les checks requis doivent être stricts (branche à jour avec main)."
  }

  assert {
    condition = (
      contains(github_branch_protection.planning_equipes_main.required_status_checks[0].contexts, "test") &&
      contains(github_branch_protection.planning_equipes_main.required_status_checks[0].contexts, "Certificat d'origine (DCO)") &&
      length(github_branch_protection.planning_equipes_main.required_status_checks[0].contexts) == 2
    )
    error_message = "required_status_checks.contexts doit reprendre exactement var.planning_equipes_required_checks."
  }
}

# L'immutabilité des releases passe par `gh api` : le chemin doit viser le
# dépôt géré ici, chez le bon propriétaire.
run "immutabilite_des_releases" {
  command = plan

  assert {
    condition     = data.external.planning_equipes_immutable_releases.program[2] == "repos/sylvainmetayer/planning-equipes/immutable-releases"
    error_message = "La lecture de l'immutabilité des releases doit viser repos/<github_owner>/<planning_equipes_repository>/immutable-releases."
  }
}
