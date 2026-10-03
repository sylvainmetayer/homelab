# Tests du module tofu/s3_state : bucket OVH qui porte le state de tous les
# autres modules, et l'utilisateur S3 qui y accède.
#
# Aucun backend, aucun credential, aucune clé SOPS : tous les providers sont
# mockés et la data source SOPS est surchargée. Les variables viennent de
# terraform.tfvars, chargé automatiquement par `tofu test`.

mock_provider "ovh" {}
mock_provider "sops" {}

# Toutes les clés lues par secrets.tf.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      OVH_CLOUD_PROJECT_ID = "fake-ovh-project-id"
    }
  }
}

run "bucket_is_the_state_backend" {
  command = plan

  assert {
    condition     = ovh_cloud_project_storage.tf_state.name == "homelab-tf-state-sylvain"
    error_message = "Le bucket doit rester homelab-tf-state-sylvain : c'est celui de tous les backend.tf."
  }

  # Tous les modules (y compris celui-ci) stockent leur state dans ce bucket :
  # le renommer sans les migrer les couperait de leur state.
  assert {
    condition = length(fileset("${path.module}/..", "*/backend.tf")) > 1 && alltrue([
      for f in fileset("${path.module}/..", "*/backend.tf") :
      can(regex("bucket\\s*=\\s*\"${ovh_cloud_project_storage.tf_state.name}\"", file("${path.module}/../${f}")))
    ])
    error_message = "Chaque tofu/*/backend.tf doit viser le bucket géré par tofu/s3_state."
  }

  assert {
    condition = alltrue([
      for f in fileset("${path.module}/..", "*/backend.tf") :
      strcontains(file("${path.module}/../${f}"), "s3.${lower(ovh_cloud_project_storage.tf_state.region_name)}.io.cloud.ovh.net") && can(regex("region\\s*=\\s*\"${lower(ovh_cloud_project_storage.tf_state.region_name)}\"", file("${path.module}/../${f}")))
    ])
    error_message = "Chaque tofu/*/backend.tf doit viser l'endpoint et la région du bucket géré par tofu/s3_state."
  }

  assert {
    condition     = output.bucket_name == ovh_cloud_project_storage.tf_state.name
    error_message = "L'output bucket_name doit exposer le nom du bucket."
  }
}

run "bucket_is_durable" {
  command = plan

  assert {
    condition     = ovh_cloud_project_storage.tf_state.region_name == "EU-WEST-PAR"
    error_message = "Le bucket doit rester en EU-WEST-PAR, seule région Object Storage OVH répliquée sur 3 AZ."
  }

  assert {
    condition     = ovh_cloud_project_storage.tf_state.versioning.status == "enabled"
    error_message = "Le versioning du bucket de state doit rester activé : c'est le seul retour arrière sur un state corrompu."
  }

  assert {
    condition     = ovh_cloud_project_storage.tf_state.encryption.sse_algorithm == "AES256"
    error_message = "Le chiffrement au repos (SSE-OMK, AES256) du bucket de state doit rester activé."
  }

  assert {
    condition     = ovh_cloud_project_storage.tf_state.service_name == "fake-ovh-project-id" && ovh_cloud_project_user.tf_state.service_name == "fake-ovh-project-id" && ovh_cloud_project_user_s3_credential.tf_state.service_name == "fake-ovh-project-id" && ovh_cloud_project_user_s3_policy.tf_state.service_name == "fake-ovh-project-id"
    error_message = "Toutes les ressources doivent être dans le projet Public Cloud OVH_CLOUD_PROJECT_ID lu dans SOPS."
  }
}

run "s3_user_policy" {
  command = plan

  assert {
    condition     = ovh_cloud_project_user.tf_state.role_name == "objectstore_operator"
    error_message = "L'utilisateur de state doit avoir le rôle objectstore_operator."
  }

  assert {
    condition = toset(jsondecode(ovh_cloud_project_user_s3_policy.tf_state.policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}",
      "arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}/*",
    ])
    error_message = "La policy S3 doit porter sur le bucket de state et ses objets, et rien d'autre."
  }

  assert {
    condition     = jsondecode(ovh_cloud_project_user_s3_policy.tf_state.policy).Statement[0].Effect == "Allow"
    error_message = "La policy S3 doit autoriser (Allow) l'accès au bucket de state."
  }

  # Le minimum dont le backend s3 a besoin pour lire, écrire et lister les
  # states (et les workspaces).
  assert {
    condition = length(setsubtract(
      ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      jsondecode(ovh_cloud_project_user_s3_policy.tf_state.policy).Statement[0].Action
    )) == 0
    error_message = "La policy S3 doit autoriser au moins GetObject, PutObject, DeleteObject et ListBucket (backend s3)."
  }

  assert {
    condition     = !contains(jsondecode(ovh_cloud_project_user_s3_policy.tf_state.policy).Statement[0].Action, "s3:*")
    error_message = "La policy S3 ne doit pas accorder s3:* : l'utilisateur de state n'a besoin que des objets."
  }
}
