# Tests du module tofu/keepass_backup : bucket versionné et deux utilisateurs
# S3 dont un seul (admin) peut supprimer des objets ailleurs que dans locks/.
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

run "bucket_is_versioned_in_a_3az_region" {
  command = plan

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.versioning.status == "enabled"
    error_message = "Le versioning du bucket doit rester activé."
  }

  assert {
    condition     = ovh_cloud_project_storage.keepass_backup.region_name == "EU-WEST-PAR"
    error_message = "Le bucket doit rester en EU-WEST-PAR (3 AZ)."
  }
}

run "writer_cannot_delete_data" {
  command = plan

  # Le writer ne doit pouvoir supprimer que sous locks/.
  assert {
    condition = alltrue([
      for st in jsondecode(ovh_cloud_project_user_s3_policy.writer.policy).Statement :
      !contains(st.Action, "s3:DeleteObject") || alltrue([for r in st.Resource : endswith(r, "/locks/*")])
    ])
    error_message = "La policy writer autorise s3:DeleteObject hors de locks/."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(ovh_cloud_project_user_s3_policy.admin.policy).Statement :
      contains(st.Action, "s3:DeleteObject")
    ])
    error_message = "La policy admin doit autoriser s3:DeleteObject (prune annuel)."
  }
}
