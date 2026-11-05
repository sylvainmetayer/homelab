# Pocket ID, fournisseur d'identité OIDC en pilote (ADR 0030, rôle Ansible
# pocket_id sur la VM Pangolin).
#
# Pas une ressource Pangolin : elle serait derrière le mur SSO qu'elle sert.
# Le routeur Traefik est dans la configuration du rôle pangolin
# (pangolin_idp_host), id.sylvain.cloud tombe déjà sur le A joker de tofu/dns.
# Ce qui suit : ses moniteurs Uptime Kuma, hors de local.websites (rien à
# générer : ni cible ni jeton d'accès), et sa déclaration côté Pangolin.
locals {
  pocket_id_issuer = "https://id.sylvain.cloud"
}

# Le document de découverte OIDC : répond 200 sans compte, et c'est ce que
# lisent Pangolin et les applis à chaque connexion. Hors Pangolin, donc sans
# page de maintenance ni jeton d'accès : un monitor de statut simple, comme
# celui du tableau de bord (website_pangolin.tf).
resource "uptimekuma_monitor_http" "pocket_id" {
  name = "Pocket ID"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "${local.pocket_id_issuer}/.well-known/openid-configuration"
  interval        = local.http_probe.interval
  timeout         = 30
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

resource "uptimekuma_monitor_push" "backup_pocket_id" {
  name = "Backup Pocket ID"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = local.backup_push_interval

  # A missed window or a pushed `down` pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_backup_pocket_id_url" {
  description = "POCKET ID - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_pocket_id.push_token}"
  sensitive   = true
}

# Pangolin comme client OIDC de Pocket ID. Absent tant que les clés SOPS du
# client (secrets.sops.yaml) n'existent pas : le client se crée dans Pocket ID
# une fois l'instance déployée, après le premier compte administrateur
# (docs/runbooks/pocket-id.md, étape 4). Le secret passe par le state, chiffré
# (encryption.tf), comme tout le reste ici.
#
# Pilote : auto_provision = false. Personne n'est créé à la première connexion
# par Pangolin : le compte externe de Sylvain est ajouté à la main dans
# l'interface, avec son rôle. Les comptes internes (le « Admin » de secours, les
# comptes Flip) ne sont ni déclarés ici ni rattachés à l'IdP : un login Pocket ID
# ne les touche jamais, il crée ou retrouve un utilisateur externe.
#
# Attributs optionnels : tous écrits, aucun optional+computed ici
# (README du module, règle du fournisseur).
locals {
  pocket_id_pangolin_client_id     = lookup(data.sops_file.secrets.data, "pocket_id_pangolin_client_id", "")
  pocket_id_pangolin_client_secret = lookup(data.sops_file.secrets.data, "pocket_id_pangolin_client_secret", "")
  pocket_id_idp_enabled            = nonsensitive(local.pocket_id_pangolin_client_id != "" && local.pocket_id_pangolin_client_secret != "")
}

resource "pangolin_idp" "pocket_id" {
  count = local.pocket_id_idp_enabled ? 1 : 0

  name    = "Pocket ID"
  variant = "oidc"

  client_id     = local.pocket_id_pangolin_client_id
  client_secret = local.pocket_id_pangolin_client_secret

  # Points d'accès de Pocket ID v2 ; l'interface du client (« Show more
  # details ») les affiche, à recopier si l'un diffère (à confirmer au premier
  # plan).
  auth_url  = "${local.pocket_id_issuer}/authorize"
  token_url = "${local.pocket_id_issuer}/api/oidc/token"

  # « groups » : sans ce scope, Pocket ID ne met pas la liste des groupes dans le
  # jeton d'identité, et une expression de rôles sur « groups » ne voit rien.
  scopes = "openid profile email groups"

  # Le nom d'utilisateur de Pocket ID, comme le guide de Pangolin : il doit
  # être celui de l'utilisateur externe créé dans Pangolin, à la lettre.
  identifier_path = "preferred_username"
  email_path      = "email"
  name_path       = "name"

  auto_provision = false
}

# L'URL de rappel que Pangolin attend, à coller dans le client « Pangolin » de
# Pocket ID (runbook, étape 4) ; null tant que l'IdP n'est pas déclaré.
output "pocket_id_pangolin_redirect_url" {
  description = "POCKET ID - URL de rappel (callback) du client Pangolin"
  value       = try(pangolin_idp.pocket_id[0].redirect_url, null)
}

# Rattache l'IdP à l'organisation. Avec auto_provision à false, Pangolin ne
# s'en sert que si un login retrouve un utilisateur externe existant ; si une
# version relit tout de même l'expression à chaque connexion (ADR 0016 :
# « rôles réécrits à chaque login »), « Member » ne peut rien élargir. Les
# groupes de Pocket ID ne passent en rôles qu'à l'étape suivante, hors pilote.
resource "pangolin_idp_org" "pocket_id" {
  count = local.pocket_id_idp_enabled ? 1 : 0

  idp_id       = pangolin_idp.pocket_id[0].id
  org_id       = local.pangolin_org_id
  role_mapping = "'Member'"
  org_mapping  = "'${local.pangolin_org_id}'"
}
