#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Apply the exact plan the plan step saved into /shared earlier in this run —
# never a fresh plan, so what the approver reviewed is what executes. The
# resulting outputs (the per-router rendered config) land in the run
# artifacts next to the plan.
set -eu

WORKDIR=/shared/tf
cd "${WORKDIR}"
mkdir -p /artifacts/new

terraform apply -input=false -no-color service.tfplan
terraform output -no-color >/artifacts/new/terraform-outputs.txt
cat /artifacts/new/terraform-outputs.txt
