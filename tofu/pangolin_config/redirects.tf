# Redirections de domaine entier, faites par Pangolin (1.25 et plus ; une
# permanente exige Badger v1.8.0 ou plus, rôle pangolin). Elles remplacent les
# routeurs écrits à la main dans le fichier dynamique de Traefik
# (pangolin_domain_redirects, retiré). Une redirection passe avant toute
# ressource et avant le SSO ; ce n'est pas une ressource, donc ni règles de
# pays ni audit d'inventaire. Le A de chaque nom vers Pangolin reste dans
# tofu/dns (pangolin.tf, redirect.tf).
#
# Seul reste dans Traefik le service worker de retrait de sylvain.dev
# (pangolin_service_worker_retirements, host_vars/pangolin) : une redirection
# ne sert aucun fichier.
#
# Tous les attributs optionnels sont déclarés, défauts compris (AGENTS.md :
# optional+computed non déclaré = dérive invisible au plan).

# memoire.epsi.sylvainmetayer.fr : un domaine Pangolin pour ce seul nom. Type
# wildcard, le seul qui se passe de délégation DNS : utilisable dès sa
# création, aucun *.memoire.epsi n'est nécessaire.
resource "pangolin_domain" "memoire_epsi" {
  base_domain          = "memoire.epsi.sylvainmetayer.fr"
  type                 = "wildcard"
  prefer_wildcard_cert = false
}

locals {
  domain_redirects = {
    # sylvain.dev est servi par Cloudflare Pages sur www (tofu/site), qui
    # n'accepte pas un apex hors zone Cloudflare. Chemin conservé.
    sylvain_dev_apex = {
      name              = "sylvain.dev vers www"
      domain_id         = local.domain_ids["sylvain.dev"]
      destination_host  = "https://www.sylvain.dev"
      permanent         = true
      rewrite_path_type = null
      rewrite_path      = null
    }
    # Lien publié sur le site (articles, CV) : le PDF de la dernière version,
    # en temporaire pour suivre une nouvelle release. Tout chemin mène au PDF.
    memoire_epsi = {
      name              = "Mémoire EPSI vers son PDF"
      domain_id         = pangolin_domain.memoire_epsi.id
      destination_host  = "https://github.com"
      permanent         = false
      rewrite_path_type = "exact"
      rewrite_path      = "/sylvainmetayer/epsi-memoire/releases/download/v1.1.1/M19_SYLVAINMETAYER.pdf"
    }
  }
}

resource "pangolin_redirect" "domain" {
  for_each = local.domain_redirects

  name              = each.value.name
  domain_id         = each.value.domain_id
  destination_host  = each.value.destination_host
  permanent         = each.value.permanent
  rewrite_path_type = each.value.rewrite_path_type
  rewrite_path      = each.value.rewrite_path

  enabled         = true
  ssl             = true
  priority        = 100
  path_match_type = "regex"
}
