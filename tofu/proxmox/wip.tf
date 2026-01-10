locals {
  # Split le token complet : "root@pam!tokenname=uuid" -> ["root@pam!tokenname", "uuid"]
  token_parts = split("=", var.proxmox_api_token)

  # Username avec le nom du token : "root@pam!tokenname"
  proxmox_username = local.token_parts[0]

  # Extraire juste le nom du token après le "!" : "root@pam!tokenname" -> "tokenname"
  token_name = length(split("!", local.token_parts[0])) > 1 ? split("!", local.token_parts[0])[1] : ""

  # Token au format attendu par Packer : "tokenname=uuid"
  proxmox_token = length(local.token_parts) > 1 ? "${local.token_name}=${local.token_parts[1]}" : ""
}
