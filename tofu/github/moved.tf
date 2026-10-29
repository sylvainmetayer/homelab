# Passage des environnements au for_each d'environments.tf (2026-10-29) :
# chaque ressource garde son objet GitHub sous sa nouvelle adresse, rien
# n'est recréé. À retirer une fois appliqué.

# production
moved {
  from = github_repository_environment.production
  to   = github_repository_environment.this["production"]
}
moved {
  from = github_repository_environment_deployment_policy.production_main
  to   = github_repository_environment_deployment_policy.main["production"]
}
moved {
  from = github_actions_environment_secret.sops_age_key
  to   = github_actions_environment_secret.this["production/SOPS_AGE_KEY"]
}
moved {
  from = github_actions_environment_secret.ssh_private_key
  to   = github_actions_environment_secret.this["production/SSH_PRIVATE_KEY"]
}
moved {
  from = github_actions_environment_secret.olm_id
  to   = github_actions_environment_secret.this["production/OLM_ID"]
}
moved {
  from = github_actions_environment_secret.olm_secret
  to   = github_actions_environment_secret.this["production/OLM_SECRET"]
}

# restore-test
moved {
  from = github_repository_environment.restore_test
  to   = github_repository_environment.this["restore-test"]
}
moved {
  from = github_repository_environment_deployment_policy.restore_test_main
  to   = github_repository_environment_deployment_policy.main["restore-test"]
}
moved {
  from = github_actions_environment_secret.restore_test_ssh_key
  to   = github_actions_environment_secret.this["restore-test/RESTORE_TEST_SSH_KEY"]
}
moved {
  from = github_actions_environment_secret.restore_test_storage_box
  to   = github_actions_environment_secret.this["restore-test/RESTORE_TEST_STORAGE_BOX"]
}
moved {
  from = github_actions_environment_secret.restore_test_borg_passphrase
  to   = github_actions_environment_secret.this["restore-test/RESTORE_TEST_BORG_PASSPHRASE"]
}
moved {
  from = github_actions_environment_secret.restore_test_push_url
  to   = github_actions_environment_secret.this["restore-test/RESTORE_TEST_PUSH_URL"]
}

# storage-box-quota
moved {
  from = github_repository_environment.storage_box_quota
  to   = github_repository_environment.this["storage-box-quota"]
}
moved {
  from = github_repository_environment_deployment_policy.storage_box_quota_main
  to   = github_repository_environment_deployment_policy.main["storage-box-quota"]
}
moved {
  from = github_actions_environment_secret.storage_box_quota_hcloud_token
  to   = github_actions_environment_secret.this["storage-box-quota/STORAGE_BOX_QUOTA_HCLOUD_TOKEN"]
}
moved {
  from = github_actions_environment_secret.storage_box_quota_push_url
  to   = github_actions_environment_secret.this["storage-box-quota/STORAGE_BOX_QUOTA_PUSH_URL"]
}

# secrets-rotation
moved {
  from = github_repository_environment.secrets_rotation
  to   = github_repository_environment.this["secrets-rotation"]
}
moved {
  from = github_repository_environment_deployment_policy.secrets_rotation_main
  to   = github_repository_environment_deployment_policy.main["secrets-rotation"]
}
moved {
  from = github_actions_environment_secret.secrets_rotation_push_url
  to   = github_actions_environment_secret.this["secrets-rotation/SECRETS_ROTATION_PUSH_URL"]
}

# trivy-ntfy et renovate-digest fusionnent dans ntfy-github. GitHub désigne
# un environnement par son nom : le renommer le remplace de toute façon
# (destruction puis création), moved ou pas. trivy-ntfy est déplacé vers
# ntfy-github, ce qui fait lire le plan comme un remplacement de l'un plutôt
# qu'une création sans lien ; renovate-digest, sans adresse d'arrivée, est
# détruit avec sa politique et son secret.
moved {
  from = github_repository_environment.trivy_ntfy
  to   = github_repository_environment.this["ntfy-github"]
}
moved {
  from = github_repository_environment_deployment_policy.trivy_ntfy_main
  to   = github_repository_environment_deployment_policy.main["ntfy-github"]
}
moved {
  from = github_actions_environment_secret.trivy_ntfy_token
  to   = github_actions_environment_secret.this["ntfy-github/NTFY_GITHUB_TOKEN"]
}
