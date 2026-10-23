# Branche main de ce dépôt (homelab) : un push sur main déploie sur les hôtes
# (deploy-docker-app.yaml). PR obligatoire, Lint et Tests verts, ni
# force-push ni suppression. Le rôle admin (le propriétaire) peut contourner,
# pour un correctif urgent poussé directement : Renovate, Copilot et les
# autres contributeurs passent par une PR. L'automerge de Renovate continue,
# il attend les mêmes checks.
resource "github_repository_ruleset" "homelab_main" {
  name        = "main"
  repository  = var.github_repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # RepositoryRole 5 : admin.
  bypass_actors {
    actor_id    = 5
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    # Noms des jobs : lint.yaml (ansible, tofu, ci) et le récapitulatif de
    # test.yaml. Pas de « branche à jour » obligatoire, pour ne pas bloquer
    # les PR Renovate.
    required_status_checks {
      strict_required_status_checks_policy = false

      required_check {
        context = "Ansible lint"
      }
      required_check {
        context = "OpenTofu lint"
      }
      required_check {
        context = "Tests"
      }
      required_check {
        context = "CI lint"
      }
    }
  }
}
