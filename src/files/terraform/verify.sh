#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Post-apply convergence check: terraform plan -detailed-exitcode against the
# state apply just wrote. Exit 0 = state matches the desired config (the step
# succeeds); exit 2 = drift remains (surfaced as a step failure so the flow
# routes to its drift terminal); exit 1 = plan error.
set -eu

WORKDIR=/shared/tf
cd "${WORKDIR}"
mkdir -p /artifacts/new

rc=0
terraform plan -input=false -no-color -detailed-exitcode \
  >/artifacts/new/terraform-verify.txt 2>&1 || rc=$?
cat /artifacts/new/terraform-verify.txt

case "${rc}" in
  0) echo "Converged: state matches the desired configuration." ;;
  2) echo "Drift detected: the state does not match the desired configuration." >&2 ;;
  *) echo "terraform plan failed (exit ${rc})." >&2 ;;
esac
exit "${rc}"
