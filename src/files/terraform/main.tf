# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Provider-less Terraform config: it declares no providers and no backend, so
# `terraform init` downloads nothing and `terraform plan` runs fully offline
# after the image is pulled. It renders the organization's effective network
# baseline (read from TF_VAR_* the flow resolves from {{ vars.* }}) as a plan
# output — a self-contained showcase of a Terraform activity.

variable "tenant" {
  type    = string
  default = "unknown"
}

variable "ntp_primary" {
  type    = string
  default = ""
}

variable "dns_primary" {
  type    = string
  default = ""
}

variable "syslog_primary" {
  type    = string
  default = ""
}

locals {
  network_baseline = {
    tenant = var.tenant
    ntp    = var.ntp_primary
    dns    = var.dns_primary
    syslog = var.syslog_primary
  }
}

output "network_baseline" {
  description = "Effective network standards for the organization running this plan."
  value       = local.network_baseline
}
