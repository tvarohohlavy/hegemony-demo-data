#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# One rolling-rollout iteration: run the server baseline playbook against a
# single host from the static inventory (--limit $TARGET_HOST — the flow's
# loop passes {{ loop.item }}). Installs ansible-core + sshpass into the
# throwaway alpine container; credentials arrive as environment variables
# resolved from the meridian-lab-ssh vault secret and are handed to Ansible
# as extra vars so they never land in the inventory file or argv of sshpass.
#
# The playbook's exit code is captured explicitly (not piped through tee) —
# it must reach the step verbatim: a failing host is what trips the flow's
# canary break edge and halts the rollout.
set -eu

: "${TARGET_HOST:?TARGET_HOST is required (the host to baseline)}"
: "${LAB_USER:?LAB_USER is required}"
: "${LAB_PASSWORD:?LAB_PASSWORD is required}"

apk add --no-cache ansible-core sshpass openssh-client >/dev/null
mkdir -p /artifacts/new

EXTRA_VARS=$(mktemp)
trap 'rm -f "${EXTRA_VARS}"' EXIT
cat >"${EXTRA_VARS}" <<EOF
ansible_user: "${LAB_USER}"
ansible_password: "${LAB_PASSWORD}"
ansible_become_password: "${LAB_PASSWORD}"
EOF

echo "Applying server baseline to ${TARGET_HOST} ..."
LOG="/artifacts/new/baseline-${TARGET_HOST}.txt"
rc=0
ansible-playbook \
  -i /attachments/hosts.ini \
  --limit "${TARGET_HOST}" \
  -e "@${EXTRA_VARS}" \
  /attachments/baseline.yml >"${LOG}" 2>&1 || rc=$?
cat "${LOG}"
exit "${rc}"
