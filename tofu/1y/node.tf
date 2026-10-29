# Version de Node du build : Pages ne lit ni mise.toml ni, avec un
# wrangler.toml, les variables du dashboard (deployment_configs.env_vars est
# ignoré au build). Elle vient donc du [vars] NODE_VERSION de wrangler.toml,
# que Renovate met à jour avec mise.toml : la postcondition bloque le plan
# s'ils divergent sur la branche de production.
#
# Propre à 1y : le wrangler.toml de ref ne déclare pas NODE_VERSION et le
# dépôt site n'a pas de wrangler.toml.
locals {
  # Première ligne `node = "…"` du fichier, c'est-à-dire celle de [tools].
  mise_node_version = try(regex("(?m)^node\\s*=\\s*[\"']([^\"']+)[\"']", data.github_repository_file.mise.content)[0], null)
}

# var.repository plutôt que le nom du dépôt géré : les fichiers sont lus au
# plan même quand le dépôt a des modifications en attente, la postcondition
# aussi.
data "github_repository_file" "mise" {
  repository = var.repository
  file       = "mise.toml"
  branch     = var.production_branch
}

data "github_repository_file" "wrangler" {
  repository = var.repository
  file       = "wrangler.toml"
  branch     = var.production_branch

  lifecycle {
    postcondition {
      # [vars] NODE_VERSION, la seule version que le build Pages lit.
      condition     = local.mise_node_version != null && try(regex("(?m)^NODE_VERSION\\s*=\\s*[\"']([^\"']+)[\"']", self.content)[0], null) == local.mise_node_version
      error_message = "Dépôt ${var.repository}, branche ${var.production_branch} : NODE_VERSION de wrangler.toml (${try(regex("(?m)^NODE_VERSION\\s*=\\s*[\"']([^\"']+)[\"']", self.content)[0], "introuvable")}) ne correspond pas à [tools] node de mise.toml (${coalesce(local.mise_node_version, "introuvable")}). Le build Pages n'utilise que wrangler.toml."
    }
  }
}
