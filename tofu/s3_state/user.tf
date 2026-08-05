# Utilisateur Public Cloud OVH dédié à l'accès S3 sur le bucket de state
# Terraform/OpenTofu (distinct du compte OVH_APPLICATION_KEY/SECRET utilisé
# par le provider ovh).
resource "ovh_cloud_project_user" "tf_state" {
  service_name = local.ovh_service_name
  description  = "tf_state"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "tf_state" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.tf_state.id
}

# Le rôle "objectstore_operator" ci-dessus autorise l'accès à l'API OVH, mais
# le protocole S3 lui-même est gouverné séparément par une policy IAM S3 :
# sans elle, tout appel S3 (aws s3 ls, backend Terraform...) reçoit un
# AccessDenied même avec des identifiants S3 valides.
resource "ovh_cloud_project_user_s3_policy" "tf_state" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.tf_state.id
  policy = jsonencode({
    "Statement" : [{
      "Sid" : "TfStateReadWrite",
      "Effect" : "Allow",
      "Action" : [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
      ],
      "Resource" : [
        "arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}",
        "arn:aws:s3:::${ovh_cloud_project_storage.tf_state.name}/*",
      ],
    }]
  })
}
