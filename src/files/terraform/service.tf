# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Desired state for a routed lab service, used by the "IaC: Terraform router
# service" flow: one terraform_data resource per target router records the
# service loopback each router must carry, and the rendered_config output is
# the exact vtysh command block the flow's netcli push step applies. Only the
# builtin terraform_data resource is used, so init/plan/apply run fully
# offline (no provider downloads) with local state kept in the run's /shared
# workspace — plan genuinely diffs against the state apply wrote earlier in
# the same run.

variable "service_name" {
  type        = string
  description = "Short service identifier stamped into the interface description."
}

variable "service_prefix" {
  type        = string
  description = "Host address the service loopback advertises (pushed as a /32)."
}

variable "routers" {
  type        = list(string)
  description = "Target routers that must carry the service loopback."
}

resource "terraform_data" "router_service" {
  for_each = toset(var.routers)

  input = {
    router      = each.value
    description = "svc ${var.service_name} managed-by-terraform"
    address     = "${var.service_prefix}/32"
  }
}

output "rendered_config" {
  description = "Per-router vtysh command block realizing the desired state."
  value = {
    for router, desired in terraform_data.router_service : router => join("\n", [
      "interface lo",
      " description ${desired.input.description}",
      " ip address ${desired.input.address}",
    ])
  }
}
