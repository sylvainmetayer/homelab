# Secret of .github/workflows/maintenance-calendar.yaml, which upserts the
# maintenance events into Sylvain's private Nextcloud calendar over CalDAV
# (.github/scripts/maintenance_caldav.py).
#
# Its own environment, readable from main only: the job needs nothing but this
# Nextcloud app password of `sylvain` (docs/runbooks/nextcloud-app-passwords.sh
# add sylvain "maintenance-homelab CI"), kept in the root secrets.sops.yaml,
# which the CI's age key cannot open. An app password reaches the whole
# account through DAV and OCS, not only this calendar: revoke it in Nextcloud
# (Paramètres personnels → Sécurité) if it leaks.
data "sops_file" "root_secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  # Value of the SOPS key until Sylvain stores the real app password: no
  # secret is pushed then (count 0, the workflow fails on its empty
  # CALDAV_PASSWORD) and the check below warns, without blocking the plan of
  # the rest of tofu/github.
  maintenance_caldav_password    = data.sops_file.root_secrets.data["nextcloud_maintenance_caldav_app_password"]
  maintenance_caldav_placeholder = "A_REMPLACER"
  # A boolean only: count cannot depend on a sensitive value (the SOPS data
  # is one), and sensitive() first keeps nonsensitive() valid when a test
  # mocks the data in clear.
  maintenance_caldav_ready = nonsensitive(sensitive(local.maintenance_caldav_password) != local.maintenance_caldav_placeholder)
}

check "maintenance_caldav_app_password_set" {
  assert {
    condition     = local.maintenance_caldav_ready
    error_message = "nextcloud_maintenance_caldav_app_password (secrets.sops.yaml racine) vaut encore A_REMPLACER : MAINTENANCE_CALDAV_APP_PASSWORD n'est pas posé. Créer le mot de passe d'application (docs/runbooks/nextcloud-app-passwords.sh add sylvain \"maintenance-homelab CI\"), sops set, puis apply."
  }
}

resource "github_repository_environment" "maintenance_calendar" {
  repository  = var.github_repository
  environment = "maintenance-calendar"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "maintenance_calendar_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.maintenance_calendar.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "maintenance_caldav_app_password" {
  count = local.maintenance_caldav_ready ? 1 : 0

  repository  = var.github_repository
  environment = github_repository_environment.maintenance_calendar.environment
  secret_name = "MAINTENANCE_CALDAV_APP_PASSWORD"
  value       = local.maintenance_caldav_password
}
