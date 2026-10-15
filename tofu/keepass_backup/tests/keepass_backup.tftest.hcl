# Tests du module tofu/keepass_backup : bucket verrouillé (Object Lock),
# versionné, avec cycle de vie, et deux utilisateurs S3 dont seul l'admin peut
# supprimer ailleurs que dans locks/.
# Providers mockés, data source SOPS surchargée, variables de terraform.tfvars.

mock_provider "ovh" {}
mock_provider "sops" {}

override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      OVH_CLOUD_PROJECT_ID = "fake-ovh-project-id"
    }
  }
}

run "bucket_is_locked_versioned_and_encrypted" {
  command = plan

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.name == "keepass-backup-sylvain"
    error_message = "Le bucket doit rester keepass-backup-sylvain : c'est l'URL du dépôt restic des dotfiles."
  }

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.region_name == "EU-WEST-PAR"
    error_message = "Le bucket doit rester en EU-WEST-PAR (3 AZ)."
  }

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.versioning.status == "enabled"
    error_message = "Le versioning du bucket doit rester activé."
  }

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.encryption.sse_algorithm == "AES256"
    error_message = "Le chiffrement SSE-OMK doit rester activé."
  }

  # Object Lock ne s'active qu'à la création : le perdre recrée le bucket.
  assert {
    condition = (
      ovh_cloud_project_storage.keepass_backup.object_lock.status == "enabled" &&
      ovh_cloud_project_storage.keepass_backup.object_lock.rule.mode == "governance"
    )
    error_message = "Object Lock en GOVERNANCE doit rester activé."
  }

  assert {
    condition = alltrue([
      ovh_cloud_project_storage.keepass_backup.service_name == "fake-ovh-project-id",
      ovh_cloud_project_user.writer.service_name == "fake-ovh-project-id",
      ovh_cloud_project_user.admin.service_name == "fake-ovh-project-id",
      ovh_cloud_project_user.writer.role_name == "objectstore_operator",
      ovh_cloud_project_user.admin.role_name == "objectstore_operator",
    ])
    error_message = "Toutes les ressources doivent viser le projet du secret SOPS, avec le rôle objectstore_operator."
  }
}

run "lifecycle_expires_locks_and_old_versions" {
  command = plan

  assert {
    condition = anytrue([
      for r in ovh_cloud_project_storage_object_bucket_lifecycle_configuration.keepass_backup.rules :
      r.filter.prefix == "locks/" && r.noncurrent_version_expiration.noncurrent_days == 1 && r.status == "enabled"
    ])
    error_message = "Une règle doit faire expirer les versions des verrous restic (locks/) après 1 jour."
  }

  assert {
    condition = anytrue([
      for r in ovh_cloud_project_storage_object_bucket_lifecycle_configuration.keepass_backup.rules :
      r.filter.prefix == "" && r.noncurrent_version_expiration.noncurrent_days > 31 && r.status == "enabled"
    ])
    error_message = "Une règle globale doit faire expirer les versions non courantes, au-delà du test mensuel."
  }
}

run "writer_cannot_delete_data" {
  command = plan

  # Toute action de suppression (ou joker) autorisée au writer ne doit viser que locks/.
  assert {
    condition = alltrue([
      for st in jsondecode(ovh_cloud_project_user_s3_policy.writer.policy).Statement :
      st.Effect != "Allow" || alltrue([
        for a in st.Action : !can(regex("^s3:(\\*|Delete)", a)) || alltrue([for r in st.Resource : endswith(r, "/locks/*")])
      ])
    ])
    error_message = "La policy writer autorise une suppression (ou s3:*) hors de locks/."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(ovh_cloud_project_user_s3_policy.writer.policy).Statement : can(tolist(st.Action))
    ])
    error_message = "Chaque Action doit être une liste."
  }

  # Le refus explicite protège même si le writer devient propriétaire du bucket.
  assert {
    condition = anytrue([
      for st in jsondecode(ovh_cloud_project_user_s3_policy.writer.policy).Statement :
      st.Effect == "Deny" && contains(st.Action, "s3:DeleteObject") &&
      contains(st.Resource, "arn:aws:s3:::keepass-backup-sylvain/data/*") &&
      contains(st.Resource, "arn:aws:s3:::keepass-backup-sylvain/snapshots/*")
    ])
    error_message = "La policy writer doit refuser explicitement la suppression des données du dépôt."
  }
}

run "admin_can_prune_and_restore_versions" {
  command = plan

  assert {
    condition = alltrue([
      for a in ["s3:DeleteObject", "s3:ListBucketVersions", "s3:GetObjectVersion"] :
      contains(jsondecode(ovh_cloud_project_user_s3_policy.admin.policy).Statement[0].Action, a)
    ])
    error_message = "L'admin doit pouvoir supprimer (prune) et lire les versions (restauration)."
  }

  assert {
    condition = alltrue([
      for st in concat(
        jsondecode(ovh_cloud_project_user_s3_policy.admin.policy).Statement,
        jsondecode(ovh_cloud_project_user_s3_policy.writer.policy).Statement,
      ) : !contains(st.Action, "s3:*")
    ])
    error_message = "Aucune policy ne doit accorder s3:*."
  }

  assert {
    condition = toset(jsondecode(ovh_cloud_project_user_s3_policy.admin.policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::keepass-backup-sylvain",
      "arn:aws:s3:::keepass-backup-sylvain/*",
    ])
    error_message = "La policy admin doit viser ce bucket et rien d'autre."
  }
}
