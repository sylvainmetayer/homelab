variable "s3_endpoint" {
  description = "Endpoint S3"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

# Bascule faite (tofu/site/README.md, étape 5) : l'apex pointe vers Pangolin.
# Repasser à false supprimerait l'enregistrement A et couperait sylvain.dev.
variable "sylvain_dev_apex_to_pangolin" {
  description = "Faire pointer l'apex sylvain.dev vers Pangolin (redirection 301 vers www)"
  type        = bool
  default     = true
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé du secrets.sops.yaml racine, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement des states tofu/pangolin (lu par terraform_remote_state)"
  type        = string
  sensitive   = true
}
