variable "github_owner" {
  description = "GitHub account/org that owns the repository"
  type        = string
  default     = "sylvainmetayer"
}

variable "github_repository" {
  description = "Repository to configure Actions secrets on"
  type        = string
  default     = "homelab"
}

variable "planning_equipes_repository" {
  description = "Name of the public repository that succeeds flip-planning"
  type        = string
  default     = "planning-equipes"
}

# Stays private until the filter-repo pass (flip-planning#198) has rewritten
# the history pushed there: a public repository is cloned and forked within
# seconds, and turning it back private does not recall those copies. Flipping
# this to "public" also turns on secret scanning and push protection, which
# GitHub only offers for free on public repositories.
variable "planning_equipes_visibility" {
  description = "Visibility of the planning-equipes repository"
  type        = string
  default     = "public"

  validation {
    condition     = contains(["private", "public"], var.planning_equipes_visibility)
    error_message = "planning_equipes_visibility must be \"private\" or \"public\"."
  }
}

# Empty on purpose. A required check that never reports leaves a pull request
# pending forever, and two reasons for that are live today: dco.yml does not
# exist yet (flip-planning#228), and every test job carries a job-level `if:`
# that skips it on fork pull requests. Fill this list once the DCO workflow is
# back and those conditions have moved from the job to its steps. Values are
# job names, or job ids when the job has no name: "test", "frontend",
# "scenario", "Certificat d'origine (DCO)".
variable "planning_equipes_required_checks" {
  description = "Status checks required on planning-equipes' main branch"
  type        = list(string)
  default     = []
}

variable "promptoramix_repository" {
  description = "Name of the repository of Promptoramix, the Linkx tournament AI"
  type        = string
  default     = "promptoramix"
}

# Ruleset « commits signés » de main (ruleset_homelab.tf). À false tant que les
# PR du dépôt fusionnent en rebase : GitHub ne signe pas les commits qu'il
# rebase. Passer à true une fois le squash en place (docs/runbooks/commits-signes.md).
variable "homelab_require_signed_commits" {
  description = "Exiger des commits signés sur la branche main du dépôt homelab"
  type        = bool
  default     = false
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé du secrets.sops.yaml racine, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement des states tofu/pangolin, tofu/github et tofu/s3_state"
  type        = string
  sensitive   = true
}
