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

# Egress guardrail self-test. This step runs under an allow-listed egress
# policy that denies the cloud metadata endpoint (169.254.169.254). Prove the
# guard is live by trying to reach it: the connect is dropped on the sandbox
# firewall, so the step's post-run egress report shows a non-zero drop count.
# Non-fatal and short (2s) so it never delays the rollout; a *reachable*
# endpoint would mean the policy is NOT being enforced, which is worth a shout.
if wget -q -T 2 -O /dev/null http://169.254.169.254/latest/meta-data/ 2>/dev/null; then
  echo "WARNING: cloud metadata endpoint was reachable — egress policy not enforced?"
else
  echo "Egress guardrail OK: metadata endpoint blocked (see the step's egress report for the drop)."
fi

apk add --no-cache ansible-core sshpass openssh-client >/dev/null
mkdir -p /artifacts/new

EXTRA_VARS=$(mktemp)
trap 'rm -f "${EXTRA_VARS}"' EXIT
# JSON is valid YAML and json.dump escapes anything a credential can
# contain — quotes or newlines in the secret cannot corrupt the vars file.
python3 - "${EXTRA_VARS}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "w") as handle:
    json.dump(
        {
            "ansible_user": os.environ["LAB_USER"],
            "ansible_password": os.environ["LAB_PASSWORD"],
            "ansible_become_password": os.environ["LAB_PASSWORD"],
        },
        handle,
    )
PY

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
