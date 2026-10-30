# Utilisateur S3 d'Ansible : lit le seul state de tofu/pangolin_config
# (ansible/tasks/pangolin_config_outputs.yml, URL push et identifiants Newt),
# sans pouvoir écrire ni lire les autres states. Ses clés vont dans
# state_s3_access_key / state_s3_secret_key de secrets/ansible.sops.yaml, que
# la CI de déploiement déchiffre : une fuite ne donne plus que ce state-là.
resource "ovh_cloud_project_user" "ansible_state_reader" {
  service_name = local.ovh_service_name
  description  = "ansible_state_reader"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "ansible_state_reader" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.ansible_state_reader.id
}

resource "ovh_cloud_project_user_s3_policy" "ansible_state_reader" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.ansible_state_reader.id
  policy = jsonencode({
    "Statement" : [
      {
        "Sid" : "ReadPangolinConfigState",
        "Effect" : "Allow",
        "Action" : ["s3:GetObject"],
        "Resource" : ["arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}/homelab/pangolin_config.tfstate"],
      },
      # amazon.aws.s3_object vérifie que le bucket existe avant de lire.
      {
        "Sid" : "SeeTheBucket",
        "Effect" : "Allow",
        "Action" : ["s3:ListBucket", "s3:GetBucketLocation"],
        "Resource" : ["arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}"],
      },
    ]
  })
}

output "ansible_state_reader_access_key" {
  description = "Access key S3 de l'utilisateur ansible_state_reader (state_s3_access_key d'Ansible)"
  value       = ovh_cloud_project_user_s3_credential.ansible_state_reader.access_key_id
}

output "ansible_state_reader_secret_key" {
  description = "Secret key S3 de l'utilisateur ansible_state_reader (state_s3_secret_key d'Ansible)"
  value       = ovh_cloud_project_user_s3_credential.ansible_state_reader.secret_access_key
  sensitive   = true
}
