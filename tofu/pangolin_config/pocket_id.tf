# Pocket ID, fournisseur d'identité OIDC en pilote (ADR 0030, rôle Ansible
# pocket_id sur la VM Pangolin).
#
# Pas une ressource Pangolin : elle serait derrière le mur SSO qu'elle sert.
# Le routeur Traefik est dans la configuration du rôle pangolin
# (pangolin_idp_host), id.sylvain.cloud tombe déjà sur le A joker de tofu/dns.
# Ce qui suit : ses moniteurs Uptime Kuma, hors de local.websites (rien à
# générer : ni cible ni jeton d'accès), et sa déclaration côté Pangolin.
locals {
  pocket_id_issuer             = "https://id.sylvain.cloud"
  pocket_id_pangolin_client_id = "pangolin"
  pocket_id_homebox_client_id  = "homebox"
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

# Les clients OIDC de Pocket ID, déclarés ici par son API (provider
# trozz/pocketid, clé d'administration STATIC_API_KEY posée par le rôle
# pocket_id) : aucun identifiant ni secret à recopier à la main. Chaque secret
# est un random_password de ce state, que Pocket ID reçoit à la création et
# que Pangolin (pangolin_idp) ou Ansible (sortie lue par docker.yml)
# reçoivent aussi : rien ne passe par SOPS ni par l'interface.
#
# Pocket ID en panne bloque le refresh de ces ressources, donc tout plan du
# module : planifier le reste avec -exclude=pocketid_client.homebox
# -exclude=pocketid_client.pangolin -exclude=pocketid_group.homebox.
#
# PKCE exigé : Pangolin et Homebox 0.27.1 l'envoient tous les deux (Pocket ID
# l'a constaté sur Pangolin, le code de Homebox crée un pkceVerifier) ; un
# client qui ne l'enverrait pas serait refusé.
#
# Les comptes de Pocket ID ne sont pas déclarés : un apply ne doit jamais
# pouvoir toucher au compte administrateur. Sylvain s'ajoute au groupe
# homebox dans l'interface (l'appartenance se règle sur l'utilisateur).
resource "random_password" "pocket_id_client" {
  for_each = toset(["pangolin", "homebox", "trek", "healthlog"])

  length  = 48
  special = false
}

resource "pocketid_group" "homebox" {
  name          = "homebox"
  friendly_name = "Homebox"
}

resource "pocketid_client" "homebox" {
  name          = "Homebox"
  client_id     = local.pocket_id_homebox_client_id
  client_secret = random_password.pocket_id_client["homebox"].result
  # Le code de Homebox 0.27.1 rappelle sans barre finale, le guide de Pocket
  # ID l'écrit avec : les deux.
  callback_urls = [
    "https://homebox.sylvain.cloud/api/v1/users/login/oidc/callback",
    "https://homebox.sylvain.cloud/api/v1/users/login/oidc/callback/",
  ]
  allowed_user_groups = [pocketid_group.homebox.id]
  # Sans URL de lancement, le client n'apparaît pas dans « Mes applications »
  # de Pocket ID (ListAccessibleOidcClients filtre dessus).
  launch_url   = "https://homebox.sylvain.cloud"
  pkce_enabled = true
  is_public    = false
}

resource "pocketid_client" "pangolin" {
  name          = "Pangolin"
  client_id     = local.pocket_id_pangolin_client_id
  client_secret = random_password.pocket_id_client["pangolin"].result
  # L'URL de rappel n'est connue qu'une fois l'IdP créé dans Pangolin. Pour
  # qu'il n'attende pas ce client, l'identifiant est fixé ici (local) plutôt
  # que lu sur la ressource : pas de cycle. Les deux clients fixent le leur
  # (sans client_id, le provider le laisse vide et seul `id` le porte).
  callback_urls = [pangolin_idp.pocket_id.redirect_url]
  launch_url    = "https://pangolin.sylvain.cloud"
  pkce_enabled  = true
  is_public     = false
}

# TREK : le foyer s'y connecte. Groupe trek pour l'accès, trek-admin pour le
# rôle admin, que TREK relit à chaque connexion dans le claim groups
# (OIDC_ADMIN_CLAIM / OIDC_ADMIN_VALUE du rôle trek) : un admin sorti de
# trek-admin redevient utilisateur à sa connexion suivante, sauf s'il est le
# dernier admin (TREK le garde).
resource "pocketid_group" "trek" {
  name          = "trek"
  friendly_name = "TREK"
}

resource "pocketid_group" "trek_admin" {
  name          = "trek-admin"
  friendly_name = "TREK admin"
}

resource "pocketid_client" "trek" {
  name          = "TREK"
  client_id     = "trek"
  client_secret = random_password.pocket_id_client["trek"].result
  # APP_URL + /api/auth/oidc/callback (oidc.controller.ts de TREK 5.0.1).
  callback_urls       = ["https://travels.sylvain.cloud/api/auth/oidc/callback"]
  allowed_user_groups = [pocketid_group.trek.id, pocketid_group.trek_admin.id]
  launch_url          = "https://travels.sylvain.cloud"
  # TREK envoie PKCE (S256).
  pkce_enabled = true
  is_public    = false
}

output "pocket_id_trek_client_id" {
  description = "POCKET ID - identifiant du client OIDC de TREK"
  value       = pocketid_client.trek.client_id
}

output "pocket_id_trek_client_secret" {
  description = "POCKET ID - secret du client OIDC de TREK"
  value       = random_password.pocket_id_client["trek"].result
  sensitive   = true
}

# HealthLog (données de santé) : Sylvain seul, groupe healthlog. Pas de rôle
# par claim ; un membre du groupe sans compte en recevrait un neuf, donc le
# groupe reste étroit. Rappel comparé octet par octet (docs/self-hosting/sso.md
# de HealthLog 1.46.5), sans barre finale.
resource "pocketid_group" "healthlog" {
  name          = "healthlog"
  friendly_name = "HealthLog"
}

resource "pocketid_client" "healthlog" {
  name                = "HealthLog"
  client_id           = "healthlog"
  client_secret       = random_password.pocket_id_client["healthlog"].result
  callback_urls       = ["https://sante.sylvain.cloud/api/auth/oidc/callback"]
  allowed_user_groups = [pocketid_group.healthlog.id]
  launch_url          = "https://sante.sylvain.cloud"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_healthlog_client_id" {
  description = "POCKET ID - identifiant du client OIDC de HealthLog"
  value       = pocketid_client.healthlog.client_id
}

output "pocket_id_healthlog_client_secret" {
  description = "POCKET ID - secret du client OIDC de HealthLog"
  value       = random_password.pocket_id_client["healthlog"].result
  sensitive   = true
}

# Lues par docker.yml pour le rôle homebox (HBOX_OIDC_CLIENT_*).
output "pocket_id_homebox_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Homebox"
  value       = pocketid_client.homebox.client_id
}

output "pocket_id_homebox_client_secret" {
  description = "POCKET ID - secret du client OIDC de Homebox"
  value       = random_password.pocket_id_client["homebox"].result
  sensitive   = true
}

# Pangolin comme client OIDC de Pocket ID.
#
# Pilote : auto_provision = false. Personne n'est créé à la première connexion
# par Pangolin : le compte externe de Sylvain est ajouté à la main dans
# l'interface, avec son rôle. Les comptes internes (le propriétaire de l'organisation, secours, les
# comptes Flip) ne sont ni déclarés ici ni rattachés à l'IdP : un login Pocket ID
# ne les touche jamais, il crée ou retrouve un utilisateur externe.
#
# Attributs optionnels : tous écrits, dont les optional+computed (variant,
# email_path, name_path, tags, auto_provision), sans quoi le plan dit « No
# changes » quel que soit l'état réel (README du module, règle du fournisseur).
resource "pangolin_idp" "pocket_id" {
  provider = pangolin.root

  name    = "Pocket ID"
  variant = "oidc"

  client_id     = local.pocket_id_pangolin_client_id
  client_secret = random_password.pocket_id_client["pangolin"].result

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
  tags            = ""

  auto_provision = false
}

# Rattache l'IdP à l'organisation. Avec auto_provision à false, Pangolin ne
# s'en sert que si un login retrouve un utilisateur externe existant ; si une
# version relit tout de même l'expression à chaque connexion (ADR 0016 :
# « rôles réécrits à chaque login »), « Member » ne peut rien élargir. Les
# groupes de Pocket ID ne passent en rôles qu'à l'étape suivante, hors pilote.
resource "pangolin_idp_org" "pocket_id" {
  provider = pangolin.root

  idp_id       = pangolin_idp.pocket_id.id
  org_id       = local.pangolin_org_id
  role_mapping = "'Member'"
  org_mapping  = "'${local.pangolin_org_id}'"
}
