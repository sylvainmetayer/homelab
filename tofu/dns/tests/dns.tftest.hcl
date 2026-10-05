# Tests du module tofu/dns : enregistrements OVH qui pointent les domaines vers
# Pangolin, challenges GitHub Pages et redirection betisier.
#
# Aucun backend, aucun credential, aucune clé SOPS : tous les providers sont
# mockés (y compris hcloud et aws, déclarés par provider.tf sans ressource), et
# les data sources SOPS et remote state sont surchargées.

mock_provider "ovh" {}
mock_provider "sops" {}
mock_provider "hcloud" {}
mock_provider "aws" {}

# Toutes les clés lues par secrets.tf.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      AWS_ACCESS_KEY_ID     = "fake-access-key"
      AWS_SECRET_ACCESS_KEY = "fake-secret-key"
    }
  }
}

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
