# Les deux domaines de l'organisation, faits hors de Tofu, importés (voir README).
# Un certificat joker par domaine (ADR 0031) : prefer_wildcard_cert et le
# résolveur DNS-01 letsencrypt-dns du Traefik de Pangolin (rôle pangolin,
# traefik_config.yml.j2). Déclarés tous deux (optionnels et calculés) : un
# changement dans l'UI se voit au plan. sylvain.cloud est réécrit à chaque
# démarrage de Pangolin depuis domain1 de sa configuration (copyInConfig.ts) :
# les deux valeurs y sont les mêmes (pangolin_wildcard_cert). Retour arrière :
# prefer_wildcard_cert = false ici ET pangolin_wildcard_cert: false (Ansible).
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
  cert_resolver        = "letsencrypt-dns"
  prefer_wildcard_cert = true
}
