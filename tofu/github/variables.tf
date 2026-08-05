variable "github_owner" {
  description = "GitHub account/org that owns the repository"
  type        = string
  default     = "sylvainmetayer"
}

variable "github_repository" {
  description = "Repository to configure Actions secrets on"
  type        = string
  default     = "homelab"
}
