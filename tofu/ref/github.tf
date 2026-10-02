# Dépôt du site de parrainage (11ty + Sveltia CMS), poussé à la main depuis
# ~/Documents/ref : pas d'auto_init, qui créerait un commit racine étranger.
resource "github_repository" "ref" {
  name         = var.repository
  description  = "Mes codes et liens de parrainage - ref.sylvain.dev"
  homepage_url = "https://${local.hostname}"
  visibility   = "public"

  topics = ["eleventy", "cloudflare-pages", "sveltia-cms"]

  auto_init = false

  # Le pied de page du site renvoie vers /issues/new (« Un code ne marche plus ? »)
  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_discussions = false

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }

    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  archive_on_destroy = true
}

resource "github_repository_vulnerability_alerts" "ref" {
  repository = github_repository.ref.name
  enabled    = true
}

# Pas de PR obligatoire : Sveltia CMS commite directement sur main depuis le
# téléphone. On protège seulement contre la perte d'historique.
resource "github_branch_protection" "ref_main" {
  repository_id = github_repository.ref.node_id
  pattern       = "main"

  enforce_admins      = false
  allows_deletions    = false
  allows_force_pushes = false
}

# Donne accès au dépôt à l'app GitHub de Cloudflare, déjà installée sur le
# compte : la première installation exige un consentement dans le navigateur,
# aucune API ne la fait. PUT /user/installations/{id}/repositories/{repo_id},
# qui n'accepte qu'un PAT classique avec le scope repo (pas le jeton OAuth de
# `gh auth token`) : voir README.md.
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = github_repository.ref.name
}
