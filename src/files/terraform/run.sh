#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Run a Terraform init + plan for the provider-less network-baseline config and
# capture the human-readable plan into the run artifacts. The hashicorp/terraform
# image's entrypoint is `terraform`, so the flow step sets entrypoint: /bin/sh to
# run this script. Inputs arrive as TF_VAR_* environment variables.
set -eu

mkdir -p /workspace /artifacts/new
cp /attachments/main.tf /workspace/main.tf
cd /workspace

terraform init -input=false -no-color
terraform plan -input=false -no-color -out=baseline.tfplan
terraform show -no-color baseline.tfplan | tee /artifacts/new/terraform-plan.txt
