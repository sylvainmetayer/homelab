terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/1y.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
    # Essai du verrou natif (écritures conditionnelles, que la doc d'OVH Object
    # Storage annonce) : un objet homelab/1y.tfstate.tflock. Si l'essai tient,
    # le mettre sur les autres backends ; sinon retirer cette ligne.
    use_lockfile = true
  }
}
