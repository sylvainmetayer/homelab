variable "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  type        = string
  default     = "https://nbg1.your-objectstorage.com"
}

variable "ci_olm_client_id" {
  description = <<-EOT
    Numeric Pangolin ID of the OLM client used by GitHub Actions CI (the one
    identified by the OLM_ID/OLM_SECRET repo secrets). Find it in the
    Pangolin dashboard under the client's settings, or via the provider's
    `pangolin_client` resource once imported. Not a secret by itself (it's
    just a numeric ID, not the OLM_ID/OLM_SECRET credential pair), but kept
    as a variable rather than hardcoded since it's an environment-specific
    value with no meaningful default.
  EOT
  type        = number
}
