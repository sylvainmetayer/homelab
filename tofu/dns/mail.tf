# Authentification des e-mails (SPF, DMARC, TLS-RPT) des quatre zones OVH.
# Procédure (lire les rapports, monter d'un cran, ajouter un expéditeur) :
# docs/runbooks/dmarc.md.
#
# Qui envoie quoi (inventaire du 2026-10-28, API OVH et dig) :
# - sylvainmetayer.fr : la boîte Infomaniak, et tout ce que les hôtes et les
#   applis envoient (pangolin_smtp_user : msmtp, Pangolin, karakeep,
#   dawarich, wishlist…). DKIM signé par Infomaniak (sélecteur
#   20230615, posé hors Tofu par Infomaniak). DMARC à p=none le temps de lire
#   les rapports.
# - sylvain.dev, metayer.dev : SimpleLogin (MX, DKIM dkim/dkim02/dkim03 en
#   CNAME vers simplelogin.co, posés hors Tofu ; le SPF est ici). DMARC déjà à quarantine strict avant ce
#   fichier : on n'ajoute que les rapports.
# - sylvain.cloud : n'envoie ni ne reçoit rien (offre e-mail OVH « redirect »
#   sans compte ni redirection, aucune appli n'écrit depuis @sylvain.cloud) :
#   verrouillé à l'envoi (SPF -all, DMARC reject) ; MX nul RFC 7505 derrière
#   sylvain_cloud_null_mx, que l'API OVH pourrait refuser.
#
# Plusieurs de ces noms existaient déjà dans la zone : ils sont importés une
# fois avec `tofu import` avant le premier apply (docs/runbooks/dmarc.md),
# jamais par un bloc import, que tofu test refuse. Sans l'import, l'apply
# créerait un second enregistrement SPF ou DMARC, et deux enregistrements DMARC
# valent aucun.

locals {
  dmarc_rua = "mailto:${var.dmarc_report_address}"

  # Politique DMARC de chaque zone. adkim/aspf = "s" exige le domaine exact
  # (pas un sous-domaine) dans DKIM d= et dans l'enveloppe.
  dmarc_policies = {
    "sylvainmetayer.fr" = { p = "none", pct = 100, strict = false }
    "sylvain.dev"       = { p = "quarantine", pct = 100, strict = true }
    "metayer.dev"       = { p = "quarantine", pct = 100, strict = true }
    "sylvain.cloud"     = { p = "reject", pct = 100, strict = true }
  }

  dmarc_records = {
    for zone, pol in local.dmarc_policies : zone => join("; ", compact([
      "v=DMARC1",
      "p=${pol.p}",
      pol.pct < 100 ? "pct=${pol.pct}" : "",
      pol.strict ? "adkim=s" : "",
      pol.strict ? "aspf=s" : "",
      "rua=${local.dmarc_rua}",
    ]))
  }

  # Rapports envoyés à une adresse d'un autre domaine que celui rapporté :
  # le domaine de l'adresse doit l'accepter (RFC 7489 §7.1), sinon les
  # récepteurs n'envoient rien.
  dmarc_report_domain = split("@", var.dmarc_report_address)[1]

  # SPF de chaque zone : un seul enregistrement par nom, sinon permerror.
  spf_records = {
    "sylvainmetayer.fr" = "v=spf1 include:spf.infomaniak.ch -all"
    "sylvain.dev"       = "v=spf1 include:simplelogin.co -all"
    "metayer.dev"       = "v=spf1 include:simplelogin.co -all"
    "sylvain.cloud"     = "v=spf1 -all"
  }

  # TLS-RPT (RFC 8460) : les zones qui reçoivent du courrier.
  tls_rpt_zones = ["sylvainmetayer.fr", "sylvain.dev", "metayer.dev"]
}

resource "ovh_domain_zone_record" "dmarc" {
  for_each = local.dmarc_records

  zone      = each.key
  subdomain = "_dmarc"
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"${each.value}\""
}

resource "ovh_domain_zone_record" "dmarc_external_report" {
  for_each = setsubtract(keys(local.dmarc_policies), [local.dmarc_report_domain])

  zone      = local.dmarc_report_domain
  subdomain = "${each.key}._report._dmarc"
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"v=DMARC1\""

  # L'autorisation se publie dans la zone de l'adresse : hors des zones OVH
  # gérées ici, l'apply échouerait (zone inconnue) et aucun rapport n'arriverait.
  lifecycle {
    precondition {
      condition     = contains(keys(local.dmarc_policies), local.dmarc_report_domain)
      error_message = "dmarc_report_address doit être sur une des zones de local.dmarc_policies (mail.tf), qui publie les autorisations <zone>._report._dmarc."
    }
  }
}

resource "ovh_domain_zone_record" "spf" {
  for_each = local.spf_records

  zone      = each.key
  subdomain = ""
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"${each.value}\""
}

resource "ovh_domain_zone_record" "tls_rpt" {
  for_each = toset(local.tls_rpt_zones)

  zone      = each.key
  subdomain = "_smtp._tls"
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"v=TLSRPTv1; rua=${local.dmarc_rua}\""
}

# MX nul (RFC 7505) : sylvain.cloud ne reçoit rien, les expéditeurs échouent
# tout de suite au lieu de réessayer vers les MX OVH. Désactivé par défaut :
# un fil du forum OVH (community.ovhcloud.com/t/3029) dit que la zone refuse
# la cible « . ». À tester d'abord dans le Manager (docs/runbooks/dmarc.md).
resource "ovh_domain_zone_record" "sylvain_cloud_null_mx" {
  count = var.sylvain_cloud_null_mx ? 1 : 0

  zone      = "sylvain.cloud"
  subdomain = ""
  fieldtype = "MX"
  ttl       = 300
  target    = "0 ."
}
