# Réglages du dépôt homelab lui-même (le dépôt qui déploie : un push sur main
# part en production). Ce fichier DÉCRIT l'état réel relevé le 11/11/2026
# (`gh api repos/sylvainmetayer/homelab`), il ne change rien : le dépôt existe
# et s'importe (tofu/github/README.md, « Dépôt homelab »). Modifier une valeur
# ici modifie le dépôt au prochain apply.
#
# Ce que le provider ne sait pas poser reste à la main (README.md) :
# approbation des workflows de PR de fork, signalement de vulnérabilité privé,
# secret PANGOLIN_ENDPOINT, environnement `copilot` (créé par l'agent Copilot).
resource "github_repository" "homelab" {
  name         = var.github_repository
  visibility   = "public"
  has_issues   = true
  has_wiki     = true
  has_projects = true

  # Ni description, ni sujets, ni Pages au 11/11 : ne pas les « corriger » ici
  # sans le vouloir.

  has_discussions = false

  # Fusion en rebase seulement (squash et merge commit désactivés). La bascule
  # vers le squash, préalable aux commits signés, passe par ces deux lignes
  # (docs/runbooks/commits-signes.md).
  allow_merge_commit     = false
  allow_squash_merge     = false
  allow_rebase_merge     = true
  allow_auto_merge       = true
  allow_update_branch    = true
  delete_branch_on_merge = true

  # Valeurs par défaut de GitHub, relevées telles quelles : les omettre ferait
  # mentir le plan le jour où le provider les enverra.
  merge_commit_title          = "MERGE_MESSAGE"
  merge_commit_message        = "PR_TITLE"
  squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"

  web_commit_signoff_required = false

  # Gratuit sur un dépôt public ; actifs au 11/11.
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }

    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  # Attributs du provider seul : l'import inscrit auto_init à false, pas
  # archive_on_destroy, qui s'affiche en « update in-place » au premier plan.
  # Cet apply envoie tout le dépôt à GitHub (PATCH), d'où l'exigence que
  # chaque valeur ci-dessus égale le réel.
  auto_init          = false
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

# Désactivées au 11/11 (GET .../vulnerability-alerts : 404 « disabled ») :
# Renovate porte les montées de version, les activer est un choix à part.
resource "github_repository_vulnerability_alerts" "homelab" {
  repository = github_repository.homelab.name
  enabled    = false
}

resource "github_repository_dependabot_security_updates" "homelab" {
  repository = github_repository.homelab.name
  enabled    = false
}

# GitHub Actions actif, toutes les actions permises (pas de liste blanche).
resource "github_actions_repository_permissions" "homelab" {
  repository      = github_repository.homelab.name
  enabled         = true
  allowed_actions = "all"
}

# GITHUB_TOKEN des workflows en lecture seule par défaut : chaque workflow
# demande ses droits en `permissions:`. Une PR ne peut pas s'auto-approuver.
resource "github_workflow_repository_permissions" "homelab" {
  repository                       = github_repository.homelab.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}
