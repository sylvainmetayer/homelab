# Pocket ID, fournisseur d'identité OIDC (ADR 0030, rôle Ansible
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
  for_each = toset(["pangolin", "homebox", "trek", "healthlog", "beszel", "dawarich", "immich", "wishlist", "karakeep", "papra", "yamtrack", "mediamanager", "nextcloud", "proxmox", "victoria-logs", "rss", "wiki", "actual", "jellyfin"])

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
  # L'admin de la supervision : le passkey à chaque connexion, même avec une
  # session Pocket ID ouverte.
  requires_reauthentication = true
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

# Immich (le foyer) : réglé dans son interface (Administration, OAuth : pas de
# variable d'env en v3.3.5, et IMMICH_CONFIG_FILE figerait tous les réglages).
# Émetteur, identifiant et secret lus par `tofu output -raw`. Rappels : la page
# de connexion, la liaison depuis les réglages utilisateur, et l'appli mobile
# (schéma app.immich, accepté par Pocket ID). Immich envoie PKCE dès que la
# découverte l'annonce. Rôle : claim immich_role du groupe immich-admin, relu à
# chaque connexion ; absent pour les autres, Immich garde alors le rôle posé.
# Un admin est aussi dans le groupe immich (mur Pangolin, accès au client).
resource "pocketid_group" "immich_admin" {
  name          = "immich-admin"
  friendly_name = "Immich admin"
  custom_claims = { immich_role = "admin" }
}

resource "pocketid_client" "immich" {
  name          = "Immich"
  client_id     = "immich"
  client_secret = random_password.pocket_id_client["immich"].result
  callback_urls = [
    "https://photos.sylvain.cloud/auth/login",
    "https://photos.sylvain.cloud/user-settings",
    "app.immich:///oauth-callback",
    # Immich Power Tools (OAuth par Immich : Immich transmet ce rappel tel quel).
    "https://power-tools.sylvain.cloud/api/auth/oauth/callback",
  ]
  allowed_user_groups = [pocketid_group.pangolin_role["immich"].id, pocketid_group.immich_admin.id]
  launch_url          = "https://photos.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/immich.svg"
  pkce_enabled        = true
  is_public           = false
}

# Wishlist (le foyer) : réglé dans son interface (Administration, OIDC), comme
# Immich. Rappel : origine + /login (src/lib/server/openid.ts, v0.69.0). PKCE
# toujours envoyé. Aucun rôle par claim : les admins se règlent dans Wishlist.
# Logo du dépôt à la version de l'image (absent de dashboard-icons).
resource "pocketid_client" "wishlist" {
  name                = "Wishlist"
  client_id           = "wishlist"
  client_secret       = random_password.pocket_id_client["wishlist"].result
  callback_urls       = ["https://cadeaux.sylvain.cloud/login"]
  allowed_user_groups = [pocketid_group.pangolin_role["wishlist"].id]
  launch_url          = "https://cadeaux.sylvain.cloud"
  logo_url            = "https://cdn.jsdelivr.net/gh/cmintey/wishlist@v0.69.0/src/lib/assets/logo.png"
  pkce_enabled        = true
  is_public           = false
}

# Karakeep (le foyer) : variables OAUTH_* du rôle karakeep. Rappel :
# NEXTAUTH_URL + /api/auth/callback/custom ; PKCE toujours. Aucun rôle par
# claim (le premier compte créé est admin).
resource "pocketid_client" "karakeep" {
  name                = "Karakeep"
  client_id           = "karakeep"
  client_secret       = random_password.pocket_id_client["karakeep"].result
  callback_urls       = ["https://keep.sylvain.cloud/api/auth/callback/custom"]
  allowed_user_groups = [pocketid_group.pangolin_role["karakeep"].id]
  launch_url          = "https://keep.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/karakeep.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_immich_client_secret" {
  description = "POCKET ID - secret du client OIDC d'Immich (saisi dans son interface)"
  value       = random_password.pocket_id_client["immich"].result
  sensitive   = true
}

# Papra (le foyer) : AUTH_PROVIDERS_CUSTOMS du rôle papra, fournisseur
# « pocket-id » (dans le rappel). Liaison par e-mail vérifié (better-auth) ;
# l'inscription fermée bloque la création d'un compte au premier login.
resource "pocketid_client" "papra" {
  name                = "Papra"
  client_id           = "papra"
  client_secret       = random_password.pocket_id_client["papra"].result
  callback_urls       = ["https://papra.sylvain.cloud/api/auth/oauth2/callback/pocket-id"]
  allowed_user_groups = [pocketid_group.pangolin_role["papra"].id]
  launch_url          = "https://papra.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/papra.svg"
  pkce_enabled        = true
  is_public           = false
}

# Yamtrack (le foyer) : SOCIALACCOUNT_PROVIDERS du rôle yamtrack (allauth,
# provider_id « pocket-id »). Aucune liaison automatique : chacun relie son
# compte depuis Réglages, Comptes, une fois connecté par mot de passe.
resource "pocketid_client" "yamtrack" {
  name                = "Yamtrack"
  client_id           = "yamtrack"
  client_secret       = random_password.pocket_id_client["yamtrack"].result
  callback_urls       = ["https://yamtrack.sylvain.cloud/accounts/oidc/pocket-id/login/callback/"]
  allowed_user_groups = [pocketid_group.pangolin_role["yamtrack"].id]
  launch_url          = "https://yamtrack.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/yamtrack.svg"
  pkce_enabled        = true
  is_public           = false
}

# MediaManager (essai, NAS) : [auth.openid_connect] du rôle mediamanager. Pas
# de PKCE (httpx-oauth 1.12.3 n'en envoie pas). Liaison par e-mail sans
# contrôle de vérification et AUCUN interrupteur d'inscription : ce groupe est
# la seule barrière, tout membre peut se créer un compte. Rappel bâti depuis
# la requête : les deux origines servies par nas_proxy (443 et 8443).
resource "pocketid_client" "mediamanager" {
  name          = "MediaManager"
  client_id     = "mediamanager"
  client_secret = random_password.pocket_id_client["mediamanager"].result
  callback_urls = [
    "https://mediamanager.sylvain.cloud/api/v1/auth/oauth/callback",
    "https://mediamanager.sylvain.cloud:8443/api/v1/auth/oauth/callback",
  ]
  allowed_user_groups = [pocketid_group.pangolin_role["mediamanager"].id]
  launch_url          = "https://mediamanager.sylvain.cloud"
  logo_url            = "https://cdn.jsdelivr.net/gh/maxdorninger/MediaManager@v1.12.3/web/static/logo.svg"
  pkce_enabled        = false
  is_public           = false
}

# Jellyfin (NAS, https://media.sylvain.cloud, ressource privée Pangolin) : le
# greffon SSO-Auth de K0lin (ansible/roles/jellyfin), fournisseur « pocketid ».
# Le groupe du rôle Pangolin jellyfin (foyer) donne l'accès, jellyfin-admin le
# statut d'administrateur (claim groups, AdminRoles du greffon). Rappel
# /sso/OID/redirect/pocketid bâti depuis la requête : les deux origines servies
# par nas_proxy (443 et 8443). PKCE : client Duende OidcClient, qui l'envoie
# par défaut (non confirmé en vrai) ; sinon Pocket ID refuserait la connexion
# et il faudrait le désactiver ici.
resource "pocketid_group" "jellyfin_admin" {
  name          = "jellyfin-admin"
  friendly_name = "Jellyfin admin"
}

resource "pocketid_client" "jellyfin" {
  name          = "Jellyfin"
  client_id     = "jellyfin"
  client_secret = random_password.pocket_id_client["jellyfin"].result
  callback_urls = [
    "https://media.sylvain.cloud/sso/OID/redirect/pocketid",
    "https://media.sylvain.cloud:8443/sso/OID/redirect/pocketid",
  ]
  allowed_user_groups = [pocketid_group.pangolin_role["jellyfin"].id, pocketid_group.jellyfin_admin.id]
  launch_url          = "https://media.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/jellyfin.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_jellyfin_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Jellyfin"
  value       = pocketid_client.jellyfin.client_id
}

output "pocket_id_jellyfin_client_secret" {
  description = "POCKET ID - secret du client OIDC de Jellyfin"
  value       = random_password.pocket_id_client["jellyfin"].result
  sensitive   = true
}

output "pocket_id_wishlist_client_secret" {
  description = "POCKET ID - secret du client OIDC de Wishlist (saisi dans son interface)"
  value       = random_password.pocket_id_client["wishlist"].result
  sensitive   = true
}

output "pocket_id_karakeep_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Karakeep"
  value       = pocketid_client.karakeep.client_id
}

output "pocket_id_karakeep_client_secret" {
  description = "POCKET ID - secret du client OIDC de Karakeep"
  value       = random_password.pocket_id_client["karakeep"].result
  sensitive   = true
}

output "pocket_id_papra_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Papra"
  value       = pocketid_client.papra.client_id
}

output "pocket_id_papra_client_secret" {
  description = "POCKET ID - secret du client OIDC de Papra"
  value       = random_password.pocket_id_client["papra"].result
  sensitive   = true
}

output "pocket_id_yamtrack_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Yamtrack"
  value       = pocketid_client.yamtrack.client_id
}

output "pocket_id_yamtrack_client_secret" {
  description = "POCKET ID - secret du client OIDC de Yamtrack"
  value       = random_password.pocket_id_client["yamtrack"].result
  sensitive   = true
}

output "pocket_id_mediamanager_client_id" {
  description = "POCKET ID - identifiant du client OIDC de MediaManager"
  value       = pocketid_client.mediamanager.client_id
}

output "pocket_id_mediamanager_client_secret" {
  description = "POCKET ID - secret du client OIDC de MediaManager"
  value       = random_password.pocket_id_client["mediamanager"].result
  sensitive   = true
}

# Nextcloud (le foyer, groupe nextcloud) : app user_oidc, fournisseur posé par
# le rôle nextcloud (occ user_oidc:provider). Liaison par uid : l'uid
# Nextcloud = le nom d'utilisateur Pocket ID (preferred_username), vérifié le
# 2026-11-06 pour les comptes du foyer. Création de compte par OIDC coupée,
# groupes (admin compris) gérés dans Nextcloud.
resource "pocketid_client" "nextcloud" {
  name          = "Nextcloud"
  client_id     = "nextcloud"
  client_secret = random_password.pocket_id_client["nextcloud"].result
  callback_urls = [
    "https://sylvain.cloud/apps/user_oidc/code",
    "https://sylvain.cloud/index.php/apps/user_oidc/code",
  ]
  allowed_user_groups = [pocketid_group.pangolin_role["nextcloud"].id]
  launch_url          = "https://sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/nextcloud.svg"
  pkce_enabled        = true
  is_public           = false
}

# Proxmox VE (hors mur Pangolin : LAN et ressource privée) : realm OpenID
# « pocketid » posé par le rôle pve_hardening (pve.yml, à la main). Les groupes
# Pocket ID deviennent les groupes PVE <groupe>-pocketid, qui portent les ACL
# (Administrator, PVEAuditor). root@pam reste le secours. Pas de PKCE :
# proxmox-openid génère un défi mais ne l'envoie pas. Rappel : l'origine de la
# page (sans chemin), une par adresse d'accès.
resource "pocketid_group" "proxmox_admin" {
  name          = "proxmox-admin"
  friendly_name = "Proxmox admin"
}

resource "pocketid_group" "proxmox_auditor" {
  name          = "proxmox-auditor"
  friendly_name = "Proxmox lecture"
}

resource "pocketid_client" "proxmox" {
  name          = "Proxmox"
  client_id     = "proxmox"
  client_secret = random_password.pocket_id_client["proxmox"].result
  callback_urls = [
    "https://pve.sylvain.cloud:8006",
    "https://192.168.1.26:8006",
  ]
  allowed_user_groups = [pocketid_group.proxmox_admin.id, pocketid_group.proxmox_auditor.id]
  launch_url          = "https://pve.sylvain.cloud:8006"
  logo_url            = "${local.pocket_id_logo_base}/proxmox.svg"
  pkce_enabled        = false
  is_public           = false
}

# VictoriaLogs (groupe victoria-logs) : SSO de vmauth (rôle victoria_logs,
# section sso: de auth.yml), rappel /_vmauth/sso/callback. vmauth n'envoie
# pas de PKCE (sso.go, v1.155.0) : client confidentiel sans. Les agents et
# Homepage gardent leurs comptes Basic.
resource "pocketid_client" "victoria_logs" {
  name                = "VictoriaLogs"
  client_id           = "victoria-logs"
  client_secret       = random_password.pocket_id_client["victoria-logs"].result
  callback_urls       = ["https://logs.sylvain.cloud/_vmauth/sso/callback"]
  allowed_user_groups = [pocketid_group.pangolin_role["victoria-logs"].id]
  launch_url          = "https://logs.sylvain.cloud/select/vmui/"
  logo_url            = "${local.pocket_id_logo_base}/victorialogs.svg"
  pkce_enabled        = false
  is_public           = false
}

# FreshRSS (le foyer, groupe rss) : mod_auth_openidc de l'image officielle
# (OIDC_* du rôle rss), auth_type http_auth : plus de formulaire web, le nom
# d'utilisateur Pocket ID est le compte FreshRSS (créé à la première connexion
# s'il n'existe pas). Rappel /i/oidc/. Sans PKCE (la configuration Apache de
# l'image n'en règle pas).
resource "pocketid_client" "rss" {
  name                = "FreshRSS"
  client_id           = "rss"
  client_secret       = random_password.pocket_id_client["rss"].result
  callback_urls       = ["https://rss.sylvain.cloud/i/oidc/"]
  allowed_user_groups = [pocketid_group.pangolin_role["rss"].id]
  launch_url          = "https://rss.sylvain.cloud/i/"
  logo_url            = "${local.pocket_id_logo_base}/freshrss.svg"
  pkce_enabled        = false
  is_public           = false
}

output "pocket_id_victoria_logs_client_id" {
  description = "POCKET ID - identifiant du client OIDC de VictoriaLogs (vmauth)"
  value       = pocketid_client.victoria_logs.client_id
}

output "pocket_id_victoria_logs_client_secret" {
  description = "POCKET ID - secret du client OIDC de VictoriaLogs (vmauth)"
  value       = random_password.pocket_id_client["victoria-logs"].result
  sensitive   = true
}

output "pocket_id_rss_client_id" {
  description = "POCKET ID - identifiant du client OIDC de FreshRSS"
  value       = pocketid_client.rss.client_id
}

output "pocket_id_rss_client_secret" {
  description = "POCKET ID - secret du client OIDC de FreshRSS"
  value       = random_password.pocket_id_client["rss"].result
  sensitive   = true
}

# BookStack (wiki, le foyer, groupe wiki) : AUTH_METHOD=oidc du rôle wiki,
# exclusif (plus de formulaire). Liaison par external_auth_id = sub Pocket ID
# (identifiant de l'utilisateur), posé à la main sur les comptes existants
# avant la bascule (runbook pocket-id). Rôles gérés dans BookStack. PKCE.
resource "pocketid_client" "wiki" {
  name                = "BookStack"
  client_id           = "wiki"
  client_secret       = random_password.pocket_id_client["wiki"].result
  callback_urls       = ["https://wiki.sylvain.cloud/oidc/callback"]
  allowed_user_groups = [pocketid_group.pangolin_role["wiki"].id]
  launch_url          = "https://wiki.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/bookstack.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_wiki_client_id" {
  description = "POCKET ID - identifiant du client OIDC de BookStack"
  value       = pocketid_client.wiki.client_id
}

output "pocket_id_wiki_client_secret" {
  description = "POCKET ID - secret du client OIDC de BookStack"
  value       = random_password.pocket_id_client["wiki"].result
  sensitive   = true
}

# Actual Budget (PikaPods, budget.sylvain.cloud, hors Pangolin : public) :
# OpenID réglé dans son interface (Paramètres, Avancé), secret par
# `tofu output -raw pocket_id_actual_client_secret`. Compte = preferred_username ;
# le premier login OpenID devient propriétaire (budgets du compte mot de passe
# repris), les suivants sont créés par lui dans l'annuaire d'Actual. Pas de
# rôle Pangolin : groupe Pocket ID dédié, seule barrière devant une appli
# publique. PKCE (S256, openid.js v26.11.0).
resource "pocketid_group" "actual" {
  name          = "actual"
  friendly_name = "Actual Budget"
}

resource "pocketid_client" "actual" {
  name                = "Actual Budget"
  client_id           = "actual"
  client_secret       = random_password.pocket_id_client["actual"].result
  callback_urls       = ["https://budget.sylvain.cloud/openid/callback"]
  allowed_user_groups = [pocketid_group.actual.id]
  launch_url          = "https://budget.sylvain.cloud"
  logo_url            = "${local.pocket_id_logo_base}/actual-budget.svg"
  pkce_enabled        = true
  is_public           = false
}

output "pocket_id_actual_client_secret" {
  description = "POCKET ID - secret du client OIDC d'Actual Budget (saisi dans son interface)"
  value       = random_password.pocket_id_client["actual"].result
  sensitive   = true
}

# Tuiles « vitrine » : chaque appli du mur sans client OIDC réel a un client
# public jamais utilisé pour se connecter, juste pour paraître dans « Mes
# applis » de Pocket ID aux membres de son groupe (= son rôle Pangolin) : le
# lanceur liste tout client à launch_url dont un groupe contient la personne
# (ListAccessibleOidcClients, v2.19.1). Le rappel est l'appli elle-même.
locals {
  # Logos hors dashboard-icons/<icon>.svg (icône absente ou mdi-), rempli
  # après vérification (curl -sI) de chaque URL.
  pocket_id_launcher_logos = {
    pairdrop          = "${local.pocket_id_mdi_base}/file-send.svg"
    speedtest_tracker = "${replace(local.pocket_id_logo_base, "/svg", "/png")}/speedtest-tracker.png"
  }

  # Icônes mdi- de Homepage, en SVG, version épinglée.
  pocket_id_mdi_base = "https://cdn.jsdelivr.net/npm/@mdi/svg@7.4.47/svg"

  # Rôles qui ont leur propre client ci-dessus : pas de vitrine en double.
  pocket_id_oidc_roles = toset([
    "homebox", "trek", "healthlog", "beszel", "dawarich", "immich", "wishlist",
    "karakeep", "papra", "yamtrack", "nextcloud", "victoria-logs", "rss", "wiki",
  ])

  pocket_id_launchers = {
    for key, website in local.websites : key => {
      name = lookup(website.homepage, "title", website.name)
      role = website.role
      icon = lookup(website.homepage, "icon", "")
    }
    if try(website.role, null) != null
    && website.homepage != null
    && try(website.enabled, true)
    && !contains(local.pocket_id_oidc_roles, website.role)
  }
}

resource "pocketid_client" "launcher" {
  for_each = local.pocket_id_launchers

  name                = each.value.name
  client_id           = "vitrine-${each.key}"
  callback_urls       = ["https://${pangolin_resource.website[each.key].full_domain}"]
  allowed_user_groups = [pocketid_group.pangolin_role[each.value.role].id]
  launch_url          = "https://${pangolin_resource.website[each.key].full_domain}"
  logo_url = lookup(local.pocket_id_launcher_logos, each.key, (
    startswith(each.value.icon, "mdi-")
    ? "${local.pocket_id_mdi_base}/${trimprefix(each.value.icon, "mdi-")}.svg"
    : "${local.pocket_id_logo_base}/${each.value.icon}.svg"
  ))
  pkce_enabled = true
  is_public    = true
}

output "pocket_id_nextcloud_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Nextcloud"
  value       = pocketid_client.nextcloud.client_id
}

output "pocket_id_nextcloud_client_secret" {
  description = "POCKET ID - secret du client OIDC de Nextcloud"
  value       = random_password.pocket_id_client["nextcloud"].result
  sensitive   = true
}

output "pocket_id_proxmox_client_id" {
  description = "POCKET ID - identifiant du client OIDC de Proxmox"
  value       = pocketid_client.proxmox.client_id
}

output "pocket_id_proxmox_client_secret" {
  description = "POCKET ID - secret du client OIDC de Proxmox"
  value       = random_password.pocket_id_client["proxmox"].result
  sensitive   = true
}

# Groupes de tout nouveau compte Pocket ID créé sans groupe choisi
# (SIGNUP_DEFAULT_USER_GROUP_IDS, rôle pocket_id) : les applis ouvertes à
# tous. Leur groupe donne aussi leur rôle Pangolin à la connexion suivante.
locals {
  pocket_id_default_groups = ["bentopdf", "enclosed", "pairdrop"]
}

output "pocket_id_default_group_ids" {
  description = "POCKET ID - groupes donnés à tout nouveau compte (rôle pocket_id)"
  value       = [for group in local.pocket_id_default_groups : pocketid_group.pangolin_role[group].id]
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
