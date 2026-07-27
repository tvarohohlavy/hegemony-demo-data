#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# One remediation pass: run the router remediation playbook against the
# routers the launch form selected (--limit $LIMIT_HOSTS, a comma-separated
# device-name list the flow renders from its inputs). Same container recipe
# as rolling.sh; the exit code is captured explicitly so an unreachable or
# still-drifting router fails the step and the flow's while-loop retries.
set -eu

: "${LIMIT_HOSTS:?LIMIT_HOSTS is required (comma-separated router names)}"
: "${LAB_USER:?LAB_USER is required}"
: "${LAB_PASSWORD:?LAB_PASSWORD is required}"

apk add --no-cache ansible-core sshpass openssh-client >/dev/null
mkdir -p /artifacts/new

EXTRA_VARS=$(mktemp)
trap 'rm -f "${EXTRA_VARS}"' EXIT
cat >"${EXTRA_VARS}" <<EOF
ansible_user: "${LAB_USER}"
ansible_password: "${LAB_PASSWORD}"
EOF

echo "Remediating routers: ${LIMIT_HOSTS} ..."
LOG="/artifacts/new/remediation.txt"
rc=0
ansible-playbook \
  -i /attachments/routers.ini \
  --limit "${LIMIT_HOSTS}" \
  -e "@${EXTRA_VARS}" \
  /attachments/remediate.yml >"${LOG}" 2>&1 || rc=$?
cat "${LOG}"
exit "${rc}"
