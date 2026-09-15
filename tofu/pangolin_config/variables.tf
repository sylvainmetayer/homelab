variable "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

# Mirrors flip_planning_keycloak_enabled on the Ansible side. The two have to
# move together: the target below would probe a container that does not exist,
# and the SSO carve-out would open a path that serves nothing.
variable "flip_planning_keycloak_enabled" {
  description = "Keycloak deployed on the /auth sub-path of the Flip Planning resource"
  type        = bool
  default     = false
}
