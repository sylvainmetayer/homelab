# Dépôt privé des secrets du homelab (ADR 0018) : les deux fichiers SOPS et
# l'inventaire de rotation, sortis du dépôt public `homelab`, qui les monte en
# sous-module à `secrets/`. Même chiffrés, ils ne sont plus publiés.
#
# Compte GitHub Free : ni ruleset ni protection de branche sur un dépôt privé
# (l'API répond 403). Ce qui le protège : privé, aucun collaborateur, une
# seule clé de déploiement en lecture seule (celle de la CI de `homelab`),
# Actions désactivées. Un force-push sur son main se verrait aussitôt : le
# commit qu'épingle le sous-module de `homelab` n'existerait plus, la CI
# échouerait au checkout ; les clones des deux postes gardent l'historique.
resource "github_repository" "homelab_secrets" {
  name        = var.homelab_secrets_repository
  description = "Secrets chiffrés (SOPS + age) du homelab, sous-module secrets/ de sylvainmetayer/homelab"
  visibility  = "private"

  # Vide : le premier push porte les fichiers copiés du dépôt public
  # (tofu/github/README.md, « Dépôt homelab-secrets »).
  auto_init = false

  has_issues      = false
  has_wiki        = false
  has_projects    = false
  has_discussions = false

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = true
  allow_auto_merge       = false
  delete_branch_on_merge = true

  # Le supprimer perdrait l'historique des secrets : on archive.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

# Aucun workflow ne tourne dans ce dépôt : les contrôles (destinataires age,
# inventaire de rotation, masquage) tournent dans le Lint de `homelab`, qui a
# besoin des playbooks.
resource "github_actions_repository_permissions" "homelab_secrets" {
  repository = github_repository.homelab_secrets.name
  enabled    = false
}

# Clé de déploiement en lecture seule : la CI de `homelab` (Lint, déploiement,
# échéances de rotation) clone le sous-module avec elle. Une nouvelle clé à
# chaque `tofu apply -replace=tls_private_key.homelab_secrets_deploy` : la clé
# publique et le secret Actions suivent dans le même apply.
resource "tls_private_key" "homelab_secrets_deploy" {
  algorithm = "ED25519"
}

resource "github_repository_deploy_key" "homelab_secrets_ci" {
  title      = "homelab CI (lecture seule)"
  repository = github_repository.homelab_secrets.name
  key        = trimspace(tls_private_key.homelab_secrets_deploy.public_key_openssh)
  read_only  = true
}

# Secret du dépôt `homelab`, pas d'un environnement : les environnements ne
# sont lisibles que depuis main, or le Lint des PR doit lire les fichiers.
# Seules les branches du dépôt même le reçoivent (pas une PR de fork, ni
# Dependabot, absent ici) ; il n'ouvre que du chiffré, ce que le dépôt public
# publiait jusqu'ici.
resource "github_actions_secret" "homelab_secrets_ssh_key" {
  repository  = var.github_repository
  secret_name = "HOMELAB_SECRETS_SSH_KEY"
  value       = tls_private_key.homelab_secrets_deploy.private_key_openssh
}
