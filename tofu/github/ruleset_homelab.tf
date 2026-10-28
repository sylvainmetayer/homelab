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

# Commits signés obligatoires sur main, dans un ruleset à part : le bypass
# admin du ruleset du dessus couvre toutes ses règles, il laisserait passer un
# push direct non signé du propriétaire. Ici, aucun bypass_actors : ce push
# doit porter sa signature SSH (keys/perso.pub, déclarée « Signing key » sur
# GitHub), et une PR n'entre que par un commit que GitHub signe lui-même
# (squash ou merge commit), après vérification de chaque commit de la branche.
#
# Le « Rebase and merge » de GitHub réécrit les commits sans pouvoir les
# signer : avec cette règle, une PR fusionnée ainsi est refusée. Le dépôt ne
# fusionne aujourd'hui qu'en rebase (squash désactivé), d'où l'interrupteur, à
# false tant que la méthode de fusion n'a pas basculé ; la précondition refuse
# le plan qui l'activerait avant. Procédure : docs/runbooks/commits-signes.md.
data "github_repository" "homelab" {
  count = var.homelab_require_signed_commits ? 1 : 0

  name = var.github_repository
}

resource "github_repository_ruleset" "homelab_main_signed_commits" {
  count = var.homelab_require_signed_commits ? 1 : 0

  name        = "main-signed-commits"
  repository  = var.github_repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    required_signatures = true
  }

  lifecycle {
    precondition {
      # GitHub refuse de désactiver les trois méthodes : sans le rebase, il
      # reste le squash ou le merge commit, que GitHub signe tous deux.
      condition     = !data.github_repository.homelab[0].allow_rebase_merge
      error_message = "Commits signés sur main : désactiver d'abord « Allow rebase merging » et autoriser le squash (docs/runbooks/commits-signes.md). GitHub ne signe pas les commits d'un rebase-merge, et Renovate fusionne en rebase tant qu'il est permis."
    }
  }
}
