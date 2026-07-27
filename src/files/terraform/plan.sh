#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Stage the router-service config into the run's /shared workspace and run
# terraform init + plan there, saving the plan file for the apply step of the
# same run (every container step of a run sees the same /shared). The
# human-readable plan is captured as a run artifact for the approval gate's
# reviewer. Inputs arrive as TF_VAR_* environment variables.
set -eu

WORKDIR=/shared/tf
mkdir -p "${WORKDIR}" /artifacts/new
cp /attachments/service.tf "${WORKDIR}/service.tf"
cd "${WORKDIR}"

terraform init -input=false -no-color
terraform plan -input=false -no-color -out=service.tfplan
terraform show -no-color service.tfplan >/artifacts/new/terraform-plan.txt
cat /artifacts/new/terraform-plan.txt
