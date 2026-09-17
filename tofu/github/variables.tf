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
