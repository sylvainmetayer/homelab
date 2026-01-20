data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  pangolin_password = data.sops_file.secrets.data["pangolin_password"]
  pangolin_secret   = data.sops_file.secrets.data["pangolin_secret"]
  smtp_user         = data.sops_file.secrets.data["smtp_user"]
  smtp_pass         = data.sops_file.secrets.data["smtp_pass"]
  le_email          = data.sops_file.secrets.data["le_email"]

  # Credentials S3 Hetzner
  s3_access_key = data.sops_file.secrets.data["AWS_ACCESS_KEY_ID"]
  s3_secret_key = data.sops_file.secrets.data["AWS_SECRET_ACCESS_KEY"]
}
