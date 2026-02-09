locals {
  talks = {
    sops: {
        record_name: "_github-pages-challenge-sylvainmetayer.sops.talks"
        record_value: "7253a83ae1e4c66c85fd1ecbaed545"
    },
    asdf: {
        record_name: "_github-pages-challenge-sylvainmetayer.asdf.talks"
        record_value: "1d363e68bd5a45e6bcb1c3c5c963c5"
    },
    ansible: {
        record_name: "_github-pages-challenge-sylvainmetayer.workstation-automation.talks"
        record_value: "d66815a90b0b498de2ab586394757f"
    }
  }
}

resource "ovh_domain_zone_record" "talks" {
  for_each = local.talks
    zone      = "sylvain.dev"
    fieldtype = "TXT"
    subdomain = each.value.record_name
    ttl       = 300
    target    = "\"${each.value.record_value}\""
}
