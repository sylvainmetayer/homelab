# Public Flip Planning demo host (ADR 0038): an OVH VPS-1, ordered once in
# the OVH console, then imported, as the provider's own guide advises for a
# service created once (docs/guides/order_consumer_key_access_rules.md):
# ordering from Tofu needs order and payment routes valid for the whole
# account, which the Tofu token (.github/scripts/ovh_credentials.py) never
# gets. Its routes here: GET /vps, GET and PUT /vps/* (read, rename).
# Import: README « Demo VPS » (no `import` block, this module is tested).
variable "demo_planning_vps" {
  description = "Service name of the demo VPS (vps-xxxxxxx.vps.ovh.net), empty until it is ordered and imported."
  type        = string
  default     = ""
}

resource "ovh_vps" "demo_planning" {
  count = var.demo_planning_vps != "" ? 1 : 0

  display_name   = "demo-planning"
  ovh_subsidiary = "FR"
  # What was ordered in the console (catalog /order/catalog/public/vps): VPS-1
  # 2027, Gravelines, Debian 13, monthly. Only read at creation, never here.
  plan = [{
    duration     = "P1M"
    plan_code    = "vps-2027-model1"
    pricing_mode = "default"
    configuration = [
      { label = "vps_datacenter", value = "GRA" },
      { label = "vps_os", value = "Debian 13" },
    ]
  }]

  lifecycle {
    # The token has no termination route anyway; a destroy would also lose the
    # IP and the host key in ansible/known_hosts.
    prevent_destroy = true
    # Order-time inputs, absent from an imported service.
    ignore_changes = [plan, plan_option, ovh_subsidiary, image_id, public_ssh_key]
  }
}

data "ovh_vps" "demo_planning" {
  count        = var.demo_planning_vps != "" ? 1 : 0
  service_name = var.demo_planning_vps
}

# Read by ansible/inventory/hetzner.py (host demo-planning).
output "demo_planning_ipv4" {
  description = "Public IPv4 of the demo VPS, empty until it is imported."
  value       = var.demo_planning_vps != "" ? try([for ip in data.ovh_vps.demo_planning[0].ips : ip if can(regex("^[0-9.]+$", ip))][0], "") : ""
}
