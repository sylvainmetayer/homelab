# Tests du module tofu/dns : enregistrements OVH qui pointent les domaines vers
# Pangolin, challenges GitHub Pages et redirection betisier.
#
# Aucun backend, aucun credential : le provider OVH est mocké et la data
# source remote state est surchargée.

# Passphrase factice du chiffrement du state (encryption.tf).
variables {
  state_encryption_passphrase = "tofu-test-passphrase-not-a-secret"
}

mock_provider "ovh" {}

# State de tofu/pangolin : seul l'output pangolin_ip est lu.
override_data {
  target = data.terraform_remote_state.pangolin
  values = {
    outputs = {
      pangolin_ip = "203.0.113.10"
    }
  }
}

run "pangolin_a_records" {
  command = plan

  assert {
    condition = alltrue([
      for r in [
        ovh_domain_zone_record.sylvain_cloud,
        ovh_domain_zone_record.sylvain_cloud_root,
        ovh_domain_zone_record.sylvain_dev,
      ] : r.fieldtype == "A" && r.target == "203.0.113.10"
    ])
    error_message = "Les enregistrements Pangolin doivent être des A vers l'IP publique de Pangolin (output pangolin_ip de tofu/pangolin)."
  }

  assert {
    condition     = ovh_domain_zone_record.sylvain_cloud.zone == "sylvain.cloud" && ovh_domain_zone_record.sylvain_cloud.subdomain == "*"
    error_message = "*.sylvain.cloud doit pointer vers Pangolin (toutes les ressources publiques Pangolin)."
  }

  assert {
    condition     = ovh_domain_zone_record.sylvain_cloud_root.zone == "sylvain.cloud" && ovh_domain_zone_record.sylvain_cloud_root.subdomain == ""
    error_message = "L'apex sylvain.cloud doit pointer vers Pangolin."
  }

  assert {
    condition     = ovh_domain_zone_record.sylvain_dev.zone == "sylvain.dev" && ovh_domain_zone_record.sylvain_dev.subdomain == "*"
    error_message = "*.sylvain.dev doit pointer vers Pangolin (démo Flip Planning, betisier...)."
  }

  assert {
    condition = alltrue([
      for r in [
        ovh_domain_zone_record.sylvain_cloud,
        ovh_domain_zone_record.sylvain_cloud_root,
        ovh_domain_zone_record.sylvain_dev,
      ] : r.ttl == 300
    ])
    error_message = "Les enregistrements Pangolin doivent garder un TTL court (300 s), pour suivre une recréation de la VM."
  }
}

# sylvain.dev est servi par Cloudflare Pages sur www (tofu/site), qui n'accepte
# pas un apex hors zone Cloudflare : l'apex pointe vers Pangolin, qui répond par
# une 301 vers www. Bascule faite : c'est la valeur par défaut.
run "apex_sylvain_dev_vers_pangolin" {
  command = plan

  assert {
    condition     = length(ovh_domain_zone_record.sylvain_dev_root) == 1
    error_message = "Bascule faite : l'apex sylvain.dev doit pointer vers Pangolin par défaut, sinon sylvain.dev est coupé."
  }

  assert {
    condition = (
      ovh_domain_zone_record.sylvain_dev_root[0].zone == "sylvain.dev"
      && ovh_domain_zone_record.sylvain_dev_root[0].subdomain == ""
      && ovh_domain_zone_record.sylvain_dev_root[0].fieldtype == "A"
      && ovh_domain_zone_record.sylvain_dev_root[0].target == "203.0.113.10"
      && ovh_domain_zone_record.sylvain_dev_root[0].ttl == 300
    )
    error_message = "L'apex sylvain.dev doit être un A vers l'IP publique de Pangolin (TTL 300) : Pangolin n'expose qu'une IPv4."
  }
}

run "apex_sylvain_dev_desactivable" {
  command = plan

  variables {
    sylvain_dev_apex_to_pangolin = false
  }

  assert {
    condition     = length(ovh_domain_zone_record.sylvain_dev_root) == 0
    error_message = "sylvain_dev_apex_to_pangolin = false ne doit poser aucun A à l'apex de sylvain.dev."
  }
}

# L'IP n'est pas écrite en dur : elle suit l'output du state de tofu/pangolin.
run "a_records_follow_pangolin_state" {
  command = plan

  override_data {
    target = data.terraform_remote_state.pangolin
    values = {
      outputs = {
        pangolin_ip = "198.51.100.7"
      }
    }
  }

  assert {
    condition = alltrue([
      for r in [
        ovh_domain_zone_record.sylvain_cloud,
        ovh_domain_zone_record.sylvain_cloud_root,
        ovh_domain_zone_record.sylvain_dev,
      ] : r.target == "198.51.100.7"
    ])
    error_message = "Les enregistrements Pangolin doivent suivre l'output pangolin_ip du state de tofu/pangolin."
  }
}

run "remote_state_reads_pangolin_module" {
  command = plan

  assert {
    condition     = data.terraform_remote_state.pangolin.backend == "s3" && data.terraform_remote_state.pangolin.config.bucket == "homelab-tf-state-sylvain"
    error_message = "Le remote state doit être lu dans le bucket S3 homelab-tf-state-sylvain."
  }

  assert {
    condition     = can(regex("key\\s*=\\s*\"${data.terraform_remote_state.pangolin.config.key}\"", file("${path.module}/../pangolin/backend.tf")))
    error_message = "La clé du remote state doit être celle du backend de tofu/pangolin."
  }

  assert {
    condition     = strcontains(file("${path.module}/../pangolin/outputs.tf"), "output \"pangolin_ip\"")
    error_message = "tofu/pangolin doit exposer l'output pangolin_ip lu ici."
  }
}

run "github_pages_challenges" {
  command = plan

  assert {
    condition     = length(ovh_domain_zone_record.talks) == 3
    error_message = "Les trois challenges GitHub Pages (sops, asdf, workstation-automation) doivent être présents."
  }

  assert {
    condition = alltrue([
      for r in values(ovh_domain_zone_record.talks) :
      r.zone == "sylvain.dev" && r.fieldtype == "TXT" && startswith(r.subdomain, "_github-pages-challenge-sylvainmetayer.") && endswith(r.subdomain, ".talks")
    ])
    error_message = "Les challenges GitHub Pages doivent être des TXT _github-pages-challenge-sylvainmetayer.<repo>.talks sur sylvain.dev."
  }

  # OVH attend la valeur d'un TXT entre guillemets.
  assert {
    condition = alltrue([
      for r in values(ovh_domain_zone_record.talks) :
      can(regex("^\"[0-9a-f]{30}\"$", r.target))
    ])
    error_message = "La valeur d'un challenge GitHub Pages doit être son code hexadécimal, entre guillemets."
  }
}

run "betisier_redirect" {
  command = plan

  assert {
    condition     = ovh_domain_zone_redirection.betisier.zone == "sylvainmetayer.fr" && ovh_domain_zone_redirection.betisier.subdomain == "betisier"
    error_message = "La redirection doit porter sur betisier.sylvainmetayer.fr."
  }

  assert {
    condition     = ovh_domain_zone_redirection.betisier.type == "visiblePermanent" && ovh_domain_zone_redirection.betisier.target == "https://betisier.sylvain.dev"
    error_message = "betisier.sylvainmetayer.fr doit rediriger (301 visible) vers https://betisier.sylvain.dev."
  }
}

run "memoire_epsi_vers_pangolin" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.memoire_epsi.zone == "sylvainmetayer.fr"
      && ovh_domain_zone_record.memoire_epsi.subdomain == "memoire.epsi"
      && ovh_domain_zone_record.memoire_epsi.fieldtype == "A"
      && ovh_domain_zone_record.memoire_epsi.target == "203.0.113.10"
    )
    error_message = "memoire.epsi.sylvainmetayer.fr doit pointer vers Pangolin, dont Traefik redirige vers le PDF du mémoire."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/host_vars/pangolin/variables.yaml"), "host: memoire.epsi.sylvainmetayer.fr")
    error_message = "La redirection de memoire.epsi.sylvainmetayer.fr doit être déclarée dans pangolin_domain_redirects (ansible/host_vars/pangolin)."
  }
}

# Vérification Google Search Console de sylvain.dev (search_console.tf) :
# posée à l'apex, car un nom porteur d'un CNAME (ref, géré par tofu/ref) ne
# peut porter aucun autre enregistrement.
run "verification_google_a_l_apex" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.sylvain_dev_google_site_verification.subdomain == "" &&
      ovh_domain_zone_record.sylvain_dev_google_site_verification.fieldtype == "TXT" &&
      ovh_domain_zone_record.sylvain_dev_google_site_verification.zone == "sylvain.dev"
    )
    error_message = "La vérification Google doit être un TXT à l'apex de sylvain.dev, pas sur ref.sylvain.dev (porteur du CNAME de tofu/ref)."
  }

  assert {
    condition = (
      startswith(ovh_domain_zone_record.sylvain_dev_google_site_verification.target, "\"google-site-verification=") &&
      endswith(ovh_domain_zone_record.sylvain_dev_google_site_verification.target, "\"")
    )
    error_message = "La valeur du TXT doit être le jeton google-site-verification=… entre guillemets."
  }
}

# media.sylvain.cloud vise l'IP LAN du NAS, pas Pangolin : un nom précis prime
# sur le joker *.sylvain.cloud. Elle suit ansible/inventory/hosts.
run "media_vers_le_nas" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.media.zone == "sylvain.cloud"
      && ovh_domain_zone_record.media.subdomain == "media"
      && ovh_domain_zone_record.media.fieldtype == "A"
      && ovh_domain_zone_record.media.target != "203.0.113.10"
      && can(regex("(?m)^\\s*nas\\s+ansible_host=${replace(ovh_domain_zone_record.media.target, ".", "\\.")}(\\s|$)", file("${path.module}/../../ansible/inventory/hosts")))
    )
    error_message = "media.sylvain.cloud doit être un A vers l'IP LAN du NAS (ansible/inventory/hosts), jamais vers Pangolin."
  }
}

# nas.sylvain.cloud (interface d'UGOS, Traefik du NAS) de même : l'IP LAN du
# NAS de l'inventaire, jamais Pangolin.
run "nas_vers_le_nas" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.nas.zone == "sylvain.cloud"
      && ovh_domain_zone_record.nas.subdomain == "nas"
      && ovh_domain_zone_record.nas.fieldtype == "A"
      && ovh_domain_zone_record.nas.target == ovh_domain_zone_record.media.target
      && can(regex("(?m)^\\s*nas\\s+ansible_host=${replace(ovh_domain_zone_record.nas.target, ".", "\\.")}(\\s|$)", file("${path.module}/../../ansible/inventory/hosts")))
    )
    error_message = "nas.sylvain.cloud doit être un A vers l'IP LAN du NAS (ansible/inventory/hosts), comme media.sylvain.cloud, jamais vers Pangolin."
  }
}

# mediamanager.sylvain.cloud (MediaManager, Traefik du NAS) de même : l'IP LAN
# du NAS de l'inventaire, jamais Pangolin.
run "mediamanager_vers_le_nas" {
  command = plan

  assert {
    condition = (
      ovh_domain_zone_record.mediamanager.zone == "sylvain.cloud"
      && ovh_domain_zone_record.mediamanager.subdomain == "mediamanager"
      && ovh_domain_zone_record.mediamanager.fieldtype == "A"
      && ovh_domain_zone_record.mediamanager.target == ovh_domain_zone_record.media.target
      && can(regex("(?m)^\\s*nas\\s+ansible_host=${replace(ovh_domain_zone_record.mediamanager.target, ".", "\\.")}(\\s|$)", file("${path.module}/../../ansible/inventory/hosts")))
    )
    error_message = "mediamanager.sylvain.cloud doit être un A vers l'IP LAN du NAS (ansible/inventory/hosts), comme media.sylvain.cloud, jamais vers Pangolin."
  }
}

# Authentification des e-mails (mail.tf, docs/runbooks/dmarc.md).
run "dmarc_sur_chaque_zone" {
  command = plan

  assert {
    condition = (
      toset(keys(ovh_domain_zone_record.dmarc)) == toset(["sylvainmetayer.fr", "sylvain.dev", "metayer.dev", "sylvain.cloud"])
      && alltrue([for z, r in ovh_domain_zone_record.dmarc : r.zone == z && r.subdomain == "_dmarc" && r.fieldtype == "TXT"])
    )
    error_message = "Chaque zone OVH doit avoir son TXT _dmarc (mail.tf)."
  }

  assert {
    condition = alltrue([
      for r in values(ovh_domain_zone_record.dmarc) :
      startswith(r.target, "\"v=DMARC1; p=") && strcontains(r.target, "; rua=mailto:dmarc@sylvainmetayer.fr")
    ])
    error_message = "Chaque DMARC doit commencer par v=DMARC1; p= et envoyer ses rapports agrégés (rua) à dmarc_report_address."
  }

  # Déjà à quarantine avant mail.tf : les rapports ne doivent pas faire
  # redescendre une politique.
  assert {
    condition = alltrue([
      for z in ["sylvain.dev", "metayer.dev"] :
      can(regex("p=(quarantine|reject)", ovh_domain_zone_record.dmarc[z].target))
    ])
    error_message = "sylvain.dev et metayer.dev étaient à p=quarantine : ne pas les redescendre à p=none."
  }
}

# Rapports adressés à un autre domaine (RFC 7489 §7.1) : le domaine de
# l'adresse doit publier <domaine rapporté>._report._dmarc, sinon aucun rapport.
run "rapports_externes_autorises" {
  command = plan

  assert {
    condition = (
      toset(keys(ovh_domain_zone_record.dmarc_external_report)) == toset(["sylvain.dev", "metayer.dev", "sylvain.cloud"])
      && alltrue([
        for z, r in ovh_domain_zone_record.dmarc_external_report :
        r.zone == "sylvainmetayer.fr" && r.subdomain == "${z}._report._dmarc" && r.target == "\"v=DMARC1\""
      ])
    )
    error_message = "sylvainmetayer.fr doit autoriser les rapports DMARC de chaque autre zone (<zone>._report._dmarc TXT v=DMARC1)."
  }
}

run "rapports_externes_suivent_l_adresse" {
  command = plan

  variables {
    dmarc_report_address = "rapports@sylvain.dev"
  }

  assert {
    condition = (
      toset(keys(ovh_domain_zone_record.dmarc_external_report)) == toset(["sylvainmetayer.fr", "metayer.dev", "sylvain.cloud"])
      && alltrue([for r in values(ovh_domain_zone_record.dmarc_external_report) : r.zone == "sylvain.dev"])
    )
    error_message = "Les autorisations de rapports externes doivent suivre le domaine de dmarc_report_address."
  }
}

run "adresse_de_rapport_invalide" {
  command = plan

  variables {
    dmarc_report_address = "a@b.fr,mailto:c@d.fr"
  }

  expect_failures = [var.dmarc_report_address]
}

run "adresse_de_rapport_hors_zones" {
  command = plan

  variables {
    dmarc_report_address = "dmarc@example.org"
  }

  expect_failures = [ovh_domain_zone_record.dmarc_external_report]
}

run "spf_un_seul_par_zone" {
  command = plan

  assert {
    condition     = toset(keys(ovh_domain_zone_record.spf)) == toset(keys(ovh_domain_zone_record.dmarc))
    error_message = "Chaque zone qui a un DMARC doit avoir son SPF ici (local.spf_records)."
  }

  assert {
    condition = alltrue([
      for z, r in ovh_domain_zone_record.spf :
      r.zone == z && r.subdomain == "" && r.fieldtype == "TXT" && can(regex("^\"v=spf1( include:[a-z0-9.-]+)* -all\"$", r.target))
    ])
    error_message = "Un SPF par zone, en TXT à l'apex, qui finit par -all."
  }

  assert {
    condition     = strcontains(ovh_domain_zone_record.spf["sylvainmetayer.fr"].target, "include:spf.infomaniak.ch")
    error_message = "sylvainmetayer.fr envoie par Infomaniak : son SPF doit inclure spf.infomaniak.ch."
  }
}

# sylvain.cloud n'envoie ni ne reçoit rien : verrouillé.
run "sylvain_cloud_verrouille" {
  command = plan

  assert {
    condition     = length(ovh_domain_zone_record.sylvain_cloud_null_mx) == 0
    error_message = "Le MX nul de sylvain.cloud reste désactivé par défaut tant que l'API OVH n'a pas accepté « 0 . »."
  }

  assert {
    condition     = ovh_domain_zone_record.spf["sylvain.cloud"].target == "\"v=spf1 -all\""
    error_message = "sylvain.cloud n'envoie rien : SPF v=spf1 -all."
  }

  assert {
    condition     = startswith(ovh_domain_zone_record.dmarc["sylvain.cloud"].target, "\"v=DMARC1; p=reject;")
    error_message = "sylvain.cloud n'envoie rien : DMARC p=reject."
  }
}

run "tls_rpt_des_zones_qui_recoivent" {
  command = plan

  assert {
    condition = (
      toset(keys(ovh_domain_zone_record.tls_rpt)) == toset(["sylvainmetayer.fr", "sylvain.dev", "metayer.dev"])
      && alltrue([
        for z, r in ovh_domain_zone_record.tls_rpt :
        r.zone == z && r.subdomain == "_smtp._tls" && r.fieldtype == "TXT" && r.target == "\"v=TLSRPTv1; rua=mailto:dmarc@sylvainmetayer.fr\""
      ])
    )
    error_message = "Chaque zone qui reçoit du courrier doit publier _smtp._tls (TLS-RPT) vers dmarc_report_address."
  }
}

run "sylvain_cloud_mx_nul" {
  command = plan

  variables {
    sylvain_cloud_null_mx = true
  }

  assert {
    condition = (
      ovh_domain_zone_record.sylvain_cloud_null_mx[0].zone == "sylvain.cloud"
      && ovh_domain_zone_record.sylvain_cloud_null_mx[0].subdomain == ""
      && ovh_domain_zone_record.sylvain_cloud_null_mx[0].fieldtype == "MX"
      && ovh_domain_zone_record.sylvain_cloud_null_mx[0].target == "0 ."
    )
    error_message = "Activé, le MX nul de sylvain.cloud doit être « 0 . » à l'apex (RFC 7505)."
  }
}

# CAA (caa.tf) : Let's Encrypt partout, plus les autorités de Cloudflare
# Pages sur sylvain.dev, aucun joker, rapports à l'adresse DMARC.
run "caa_sur_chaque_zone" {
  command = plan

  assert {
    condition = (
      toset([for r in values(ovh_domain_zone_record.caa) : r.zone]) == toset(keys(ovh_domain_zone_record.dmarc))
      && alltrue([for r in values(ovh_domain_zone_record.caa) : r.subdomain == "" && r.fieldtype == "CAA" && r.ttl == 300])
    )
    error_message = "Chaque zone OVH doit porter ses CAA à l'apex (caa.tf)."
  }

  assert {
    condition = alltrue([
      for z in keys(ovh_domain_zone_record.dmarc) :
      ovh_domain_zone_record.caa["${z} issue letsencrypt.org"].target == "0 issue \"letsencrypt.org\""
      && ovh_domain_zone_record.caa["${z} issuewild"].target == "0 issuewild \";\""
      && ovh_domain_zone_record.caa["${z} iodef"].target == "0 iodef \"mailto:dmarc@sylvainmetayer.fr\""
    ])
    error_message = "Chaque zone : issue letsencrypt.org, issuewild \";\" (aucun joker) et iodef vers dmarc_report_address."
  }

  # Seul sylvain.dev porte des noms Cloudflare Pages : ailleurs, Let's Encrypt seul.
  assert {
    condition = toset([
      for k, r in ovh_domain_zone_record.caa : k
      if startswith(r.target, "0 issue ") && r.target != "0 issue \"letsencrypt.org\""
    ]) == toset(["sylvain.dev issue pki.goog", "sylvain.dev issue ssl.com"])
    error_message = "Hors Let's Encrypt, seules les autorités de Cloudflare Pages (pki.goog, ssl.com) sont autorisées, et seulement sur sylvain.dev."
  }

  # Les CNAME de Pages visent *.pages.dev, sans CAA : la recherche remonte à
  # l'apex de leur zone, qui doit autoriser les trois autorités de Cloudflare.
  assert {
    condition = alltrue(flatten([
      for m in ["ref", "site", "1y"] : [
        for ca in ["letsencrypt.org", "pki.goog", "ssl.com"] :
        contains(keys(ovh_domain_zone_record.caa), "${regex("variable \"domain_zone\"[^}]*default\\s*=\\s*\"([^\"]+)\"", file("${path.module}/../${m}/variables.tf"))[0]} issue ${ca}")
      ]
    ]))
    error_message = "La zone des domaines Cloudflare Pages (tofu/ref, site, 1y) doit autoriser letsencrypt.org, pki.goog et ssl.com, sinon leurs certificats ne se renouvellent plus."
  }

  # issuewild ";" suppose qu'aucun joker n'est demandé : Pangolin n'en
  # demande que si prefer_wildcard_cert est activé.
  assert {
    condition     = !can(regex("prefer_wildcard_cert:\\s*true", file("${path.module}/../../ansible/roles/pangolin/templates/pangolin_config.yml.j2")))
    error_message = "Pangolin demanderait un certificat joker, que le CAA issuewild \";\" refuse : autoriser letsencrypt.org en issuewild sur sa zone (caa.tf)."
  }
}

run "caa_iodef_suit_l_adresse" {
  command = plan

  variables {
    dmarc_report_address = "rapports@sylvain.dev"
  }

  assert {
    condition     = ovh_domain_zone_record.caa["metayer.dev iodef"].target == "0 iodef \"mailto:rapports@sylvain.dev\""
    error_message = "L'iodef des CAA doit suivre dmarc_report_address."
  }
}
