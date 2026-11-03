# Les deux domaines de l'organisation, faits hors de Tofu, importés (voir README).
# prefer_wildcard_cert vaut déjà false : déclaré, un changement dans l'UI se voit
# au plan. cert_resolver est null partout : un null ne s'épingle pas.
#
# local.domain_ids reste lu par data.pangolin_domains.all (nodes.tf), pour ne pas
# faire dépendre chaque ressource publique de ces imports.
#
# sylvain.cloud est aussi déclaré dans la configuration de Pangolin (domain1, rôle
# pangolin) : l'API refuse de le supprimer. sylvain.dev, lui, se supprimerait : un
# changement de base_domain ou de type le recréerait, relire le plan en cas de
# diff. Pas de prevent_destroy : les runs `apply` de `tofu test` détruisent ce
# qu'ils créent.
resource "pangolin_domain" "org" {
  for_each = toset(["sylvain.cloud", "sylvain.dev"])

  base_domain          = each.value
  type                 = "wildcard"
  prefer_wildcard_cert = false
}
