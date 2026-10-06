variable "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

# Countries opened on top of local.allowed_countries for a trip, each until a
# date. The filter only moves when someone runs `tofu apply`: an entry whose
# date has passed stops producing rules at the next plan, so the first apply
# after coming home closes the country again without anyone editing this file.
# Nothing applies on a schedule here, so until that apply the country stays
# open - the `travel_countries_stale` check in rules.tf says so on every plan.
variable "travel_countries" {
  description = "Pays ouverts temporairement (voyage) : code ISO 3166-1 alpha-2 => fin d'ouverture (RFC 3339, UTC)."
  type        = map(string)
  default = {
    # Édimbourg, du 7 au 14 octobre 2026, un jour de marge pour le retour.
    GB = "2026-10-16T00:00:00Z"
  }

  validation {
    condition     = alltrue([for country in keys(var.travel_countries) : can(regex("^[A-Z]{2}$", country))])
    error_message = "Les clés de travel_countries sont des codes pays ISO 3166-1 alpha-2 en majuscules (GB, IT...)."
  }

  validation {
    condition     = alltrue([for until in values(var.travel_countries) : can(timecmp(until, until))])
    error_message = "Les dates de fin de travel_countries sont au format RFC 3339, par exemple 2026-10-16T00:00:00Z."
  }
}
