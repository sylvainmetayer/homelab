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

  # Logos des clients (« Mes applications » et écran de consentement), que
  # Pocket ID télécharge à l'apply : dashboard-icons, comme Homepage, figé sur
  # un commit. Jamais l'adresse de l'appli elle-même : derrière le mur SSO, le
  # téléchargement échouerait.
  pocket_id_logo_base = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@16c42dc580c144246651d322a079e535cb2b69f8/svg"

  # Les rôles Pangolin repris des groupes Pocket ID : tous ceux d'applis
  # (roles.tf), plus ceux des ressources privées (private_resources.tf).
  pocket_id_role_groups = toset(concat(local.apps, ["jellyfin", "mediamanager"]))
  # Ceux dont l'appli est branchée sur Pocket ID ont leur propre ressource
  # pocketid_group (plus bas) : pas de second groupe du même nom, que Pocket
  # ID refuserait à l'apply.
  pocket_id_app_groups = toset(["homebox", "trek", "healthlog", "beszel", "dawarich"])
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
  for_each = toset(["pangolin", "homebox", "trek", "healthlog", "beszel", "dawarich"])

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
  logo_url     = "${local.pocket_id_logo_base}/homebox.svg"
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
  logo_url      = "${local.pocket_id_logo_base}/pangolin.svg"
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
  # Absent de dashboard-icons : l'icône du dépôt TREK, à la version de l'image.
  logo_url = "https://raw.githubusercontent.com/mauriceboe/TREK/v5.0.1/client/public/icons/icon.svg"
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
# par claim. L'inscription de HealthLog est fermée : le SSO ne crée aucun
# compte (oidc_registration_disabled), il ne relie que l'existant. Rappel comparé octet par octet (docs/self-hosting/sso.md
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
  logo_url            = "${local.pocket_id_logo_base}/healthlog.svg"
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

# Beszel : Sylvain seul, groupe beszel. Le fournisseur se règle dans l'admin
# PocketBase du hub (collection users, OAuth2), pas par l'environnement : le
# secret se lit par `tofu output -raw pocket_id_beszel_client_secret`, dans un
# terminal, jamais dans une conversation. USER_CREATION reste à false (défaut) :
# le SSO ne crée aucun compte, le rôle reste celui du compte Beszel.
resource "pocketid_group" "beszel" {
  name          = "beszel"
  friendly_name = "Beszel"
}

resource "pocketid_client" "beszel" {
  name                = "Beszel"
  client_id           = "beszel"
  client_secret       = random_password.pocket_id_client["beszel"].result
  callback_urls       = ["https://monitoring.sylvain.cloud/api/oauth2-redirect"]
  allowed_user_groups = [pocketid_group.beszel.id]
  launch_url          = "https://monitoring.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/beszel.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_beszel_client_secret" {
  description = "POCKET ID - secret du client OIDC de Beszel (à saisir dans l'admin PocketBase)"
  value       = random_password.pocket_id_client["beszel"].result
  sensitive   = true
}

# Dawarich : le foyer, groupe dawarich. Pas de rôle par claim (l'admin est un
# drapeau du compte Dawarich). OIDC_AUTO_REGISTER=false (rôle dawarich) : le
# SSO ne crée aucun compte ; un compte existant se relie par un défi (mot de
# passe Dawarich) à la première connexion, e-mail vérifié exigé.
resource "pocketid_group" "dawarich" {
  name          = "dawarich"
  friendly_name = "Dawarich"
}

resource "pocketid_client" "dawarich" {
  name                = "Dawarich"
  client_id           = "dawarich"
  client_secret       = random_password.pocket_id_client["dawarich"].result
  callback_urls       = ["https://tracks.sylvain.cloud/users/auth/openid_connect/callback"]
  allowed_user_groups = [pocketid_group.dawarich.id]
  launch_url          = "https://tracks.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/dawarich.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_dawarich_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Dawarich"
  value       = pocketid_client.dawarich.client_id
}

output "pocket_id_dawarich_client_secret" {
  description = "POCKET ID - secret du client OIDC de Dawarich"
  value       = random_password.pocket_id_client["dawarich"].result
  sensitive   = true
}

# L'émetteur OIDC, lu par les rôles des applis branchées (homebox, trek,
# healthlog, dawarich) : une seule source pour l'URL de Pocket ID.
output "pocket_id_issuer" {
  description = "POCKET ID - URL de l'émetteur OIDC"
  value       = local.pocket_id_issuer
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
# auto_provision = true : Pangolin crée l'utilisateur externe à sa première
# connexion par Pocket ID et lui réécrit ses rôles à chaque connexion, d'après
# ses groupes Pocket ID (pangolin_idp_org plus bas). Les droits d'une personne
# se règlent donc dans Pocket ID seul. Un utilisateur externe créé à la main
# avant (autoProvisioned = false) n'est jamais synchronisé : le supprimer, il
# revient à sa connexion suivante. Les comptes internes (le propriétaire de
# l'organisation, compte de secours, les comptes Flip, le foyer pas encore
# passé à Pocket ID) ne sont ni déclarés ici ni rattachés à l'IdP : un login
# Pocket ID ne les touche jamais, leurs rôles restent ceux de l'interface.
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

  auto_provision = true
}

# Rattache l'IdP à l'organisation. Rôles = groupes Pocket ID dont le nom est
# celui d'un rôle d'appli (local.pocket_id_role_groups) : jamais Admin ni
# Member, même si un groupe Pocket ID portait ce nom. Une liste de plusieurs
# rôles n'est gardée en entier qu'avec la licence Enterprise activée
# (fullRbac) ; sans elle, Pangolin 1.25.3 ne garde que le premier, sans le
# dire. Aucun groupe reconnu : connexion refusée (« No policies matched »).
resource "pangolin_idp_org" "pocket_id" {
  provider = pangolin.root

  idp_id       = pangolin_idp.pocket_id.id
  org_id       = local.pangolin_org_id
  role_mapping = "groups[?contains(`${jsonencode(sort(local.pocket_id_role_groups))}`, @)]"
  org_mapping  = "'${local.pangolin_org_id}'"
}

# Un groupe Pocket ID par rôle Pangolin d'appli, du même nom : y mettre
# quelqu'un lui donne la ressource Pangolin à sa connexion suivante. Les
# applis branchées sur Pocket ID ont déjà le leur (plus haut, filtre
# allowed_user_groups de leur client) ; un admin d'appli (trek-admin) est
# membre des deux groupes, sinon le mur Pangolin l'arrête.
resource "pocketid_group" "pangolin_role" {
  for_each = setsubtract(local.pocket_id_role_groups, local.pocket_id_app_groups)

  name = each.key
  # Nom affiché comme ceux des applis branchées (« Homebox », « TREK ») ; les
  # sigles et graphies que title() casserait sont écrits à la main.
  friendly_name = lookup({
    rss                = "RSS"
    ntfy               = "ntfy"
    bentopdf           = "BentoPDF"
    pairdrop           = "PairDrop"
    "demo-planning-kc" = "Demo Planning KC"
    mediamanager       = "MediaManager"
    "victoria-logs"    = "VictoriaLogs"
  }, each.key, title(replace(each.key, "-", " ")))
}
