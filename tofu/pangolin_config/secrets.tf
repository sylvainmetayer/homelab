data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  pangolin_org_id  = data.sops_file.secrets.data["pangolin_org_id"]
  pangolin_url     = data.sops_file.secrets.data["pangolin_url"]
  pangolin_api_key = data.sops_file.secrets.data["pangolin_api_key"]

  # Bot and chat of the Telegram notification (notifications.tf).
  telegram_bot_token = data.sops_file.secrets.data["uptimekuma_telegram_bot_token"]
  telegram_chat_id   = data.sops_file.secrets.data["uptimekuma_telegram_chat_id"]

  uptimekuma_endpoint = data.sops_file.secrets.data["UPTIMEKUMA_ENDPOINT"]
  uptimekuma_username = data.sops_file.secrets.data["UPTIMEKUMA_USERNAME"]
  uptimekuma_password = data.sops_file.secrets.data["UPTIMEKUMA_PASSWORD"]
  home_ip             = data.sops_file.secrets.data["home_ip"]
  immich_pin          = data.sops_file.secrets.data["immich_pin"]

  # Write-only token of ntfy's uptime-kuma producer (website_ntfy.tf).
  ntfy_uptime_kuma_token = data.sops_file.secrets.data["ntfy_uptime_kuma_token"]

}
