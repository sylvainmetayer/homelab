data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  pangolin_org_id  = data.sops_file.secrets.data["pangolin_org_id"]
  pangolin_url     = data.sops_file.secrets.data["pangolin_url"]
  pangolin_api_key = data.sops_file.secrets.data["pangolin_api_key"]

  # Credentials S3 Hetzner
  s3_access_key = data.sops_file.secrets.data["AWS_ACCESS_KEY_ID"]
  s3_secret_key = data.sops_file.secrets.data["AWS_SECRET_ACCESS_KEY"]

  # Infomaniak mailbox already used to send Pangolin's own transactional mail.
  smtp_user = data.sops_file.secrets.data["smtp_user"]
  smtp_pass = data.sops_file.secrets.data["smtp_pass"]

  # Where downtime alerts go. Reuses the Let's Encrypt contact address, which is
  # already the admin mailbox for this infrastructure - no new secret to manage.
  alert_email = data.sops_file.secrets.data["le_email"]

  uptimekuma_endpoint = data.sops_file.secrets.data["UPTIMEKUMA_ENDPOINT"]
  uptimekuma_username = data.sops_file.secrets.data["UPTIMEKUMA_USERNAME"]
  uptimekuma_password = data.sops_file.secrets.data["UPTIMEKUMA_PASSWORD"]
  home_ip             = data.sops_file.secrets.data["home_ip"]
  immich_pin          = data.sops_file.secrets.data["immich_pin"]

}
