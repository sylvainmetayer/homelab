data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  # Credentials S3 Hetzner
  s3_access_key = data.sops_file.secrets.data["AWS_ACCESS_KEY_ID"]
  s3_secret_key = data.sops_file.secrets.data["AWS_SECRET_ACCESS_KEY"]
}
