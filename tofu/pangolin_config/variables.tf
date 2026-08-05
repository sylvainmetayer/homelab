variable "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  type        = string
  default     = "https://nbg1.your-objectstorage.com"
}

variable "ci_olm_client_id" {
  description = <<-EOT
    Numeric Pangolin ID of the OLM client used by GitHub Actions CI - the
    one identified by the OLM_ID/OLM_SECRET repo secrets. Default is the
    "runner" client (GET /v1/org/{org}/clients), the only OLM client
    currently registered. Not a secret by itself (just a numeric ID, not
    the OLM_ID/OLM_SECRET credential pair).
  EOT
  type        = number
  default     = 6
}
