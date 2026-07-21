#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Provision the demo Gitea so the backup integrations have somewhere to push:
# wait for health, create the admin account and a public org, then create the
# auto-initialised backup repositories:
#   * config-backups   — pushed to by the "Ops: Backup lab configs to Git" flow
#                        from inside its own container (HTTP basic auth).
#   * flow-backups     — Hegemony's native flow Git-sync writes flow definitions
#                        here (see the flow's Git section in the demo bundle).
#   * platform-backups — the "Meridian platform config backup" Platform Sync
#                        profile (imported from the bundle) exports platform
#                        config here; run its export from the Platform Sync UI.
#
# The two native-write repos need a credential: Hegemony authenticates git over
# HTTP by sending the fixed username "x-access-token" and a secret value as the
# Basic-auth password. Rather than mint an access token (a random value that
# would have to be captured and stored — and must never reach run/container
# logs), this seed provisions a dedicated Gitea SERVICE ACCOUNT literally named
# "x-access-token" whose password IS the meridian-gitea-token secret, and grants
# it write on the two backup repos. Gitea, seeing a password that is not an
# access token, falls back to a normal username+password login — so the backups
# authenticate out of the box with no token to mint or print. The password comes
# in as WRITE_PASSWORD (resolved from the same secret Hegemony reads), so the two
# ends always match.
# Idempotent — safe to re-run.
set -e

GITEA_CONTAINER="${GITEA_CONTAINER:-meridian-gitea}"
BASE="${GITEA_URL:-http://host.docker.internal:3000}"
ADMIN_USER="${ADMIN_USER:-meridian-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-demo-gitea-admin-password}"
ORG="${GITEA_ORG:-meridian}"
# The service account Hegemony authenticates as. Its name MUST equal the fixed
# username Hegemony's git client sends (see apps/api/services/git_ops.py).
GIT_USER="x-access-token"
WRITE_PASSWORD="${WRITE_PASSWORD:-}"

# Call a Gitea API endpoint with the admin credentials, treating a genuine
# duplicate (409/422) as an idempotent success but surfacing auth/network/server
# failures instead of masking them all as "already exists". Never echoes the
# request body, so secrets passed in ${data} stay out of logs.
#   gitea_api "<description>" <METHOD> <url> [json-body]
gitea_api() {
  desc="$1"
  method="$2"
  url="$3"
  data="$4"
  echo "Provisioning ${desc} (idempotent) ..."
  if [ -n "${data}" ]; then
    status=$(curl -sS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X "${method}" "${url}" \
      -H 'Content-Type: application/json' -d "${data}" \
      -o /dev/null -w '%{http_code}') || {
      echo "ERROR: request for ${desc} failed (network/connection)" >&2
      return 1
    }
  else
    status=$(curl -sS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X "${method}" "${url}" \
      -o /dev/null -w '%{http_code}') || {
      echo "ERROR: request for ${desc} failed (network/connection)" >&2
      return 1
    }
  fi
  case "${status}" in
    200 | 201 | 204) echo "  ${desc}: ok (HTTP ${status})." ;;
    409 | 422) echo "  ${desc}: already exists; continuing." ;;
    *)
      echo "ERROR: ${desc} returned HTTP ${status}" >&2
      return 1
      ;;
  esac
}

echo "Waiting for Gitea at ${BASE} ..."
HEALTHY=false
for _ in $(seq 1 60); do
  if curl -fsS "${BASE}/api/healthz" >/dev/null 2>&1; then
    echo "Gitea is healthy."
    HEALTHY=true
    break
  fi
  sleep 2
done
if [ "${HEALTHY}" != "true" ]; then
  echo "ERROR: Gitea did not become healthy within 120s" >&2
  exit 1
fi

echo "Creating admin user ${ADMIN_USER} (idempotent) ..."
docker exec "${GITEA_CONTAINER}" gitea admin user create \
  --username "${ADMIN_USER}" \
  --password "${ADMIN_PASSWORD}" \
  --email "${ADMIN_USER}@meridian.example" \
  --admin --must-change-password=false \
  || echo "admin user already exists; continuing"

gitea_api "org ${ORG}" POST "${BASE}/api/v1/orgs" \
  "{\"username\":\"${ORG}\",\"visibility\":\"public\"}"

for REPO in config-backups flow-backups platform-backups; do
  gitea_api "${REPO} repository" POST "${BASE}/api/v1/orgs/${ORG}/repos" \
    "{\"name\":\"${REPO}\",\"private\":false,\"auto_init\":true,\"default_branch\":\"main\"}"
done

# --- Native-write backups: the Hegemony service account -------------------
# Provision the "x-access-token" account and give it write on the two repos
# Hegemony pushes to. With no real password we cannot create the account, so
# skip gracefully (the anonymous reads still work; only the pushes would fail).
if [ -z "${WRITE_PASSWORD}" ] || [ "${WRITE_PASSWORD}" = "DEMO_GITEA_WRITE_TOKEN_PLACEHOLDER" ]; then
  echo "meridian-gitea-token is unset/placeholder; skipping the ${GIT_USER} service account."
  echo "  Set the meridian-gitea-token secret and re-run the Lab flow to enable native git backups."
else
  gitea_api "service account ${GIT_USER}" POST "${BASE}/api/v1/admin/users" \
    "{\"username\":\"${GIT_USER}\",\"full_name\":\"Hegemony backup service account\",\"email\":\"${GIT_USER}@meridian.example\",\"password\":\"${WRITE_PASSWORD}\",\"must_change_password\":false}"
  # Converge the password to the current secret value on every run, so rotating
  # the secret and re-running the flow keeps the two ends in sync.
  gitea_api "service account password" PATCH "${BASE}/api/v1/admin/users/${GIT_USER}" \
    "{\"login_name\":\"${GIT_USER}\",\"source_id\":0,\"password\":\"${WRITE_PASSWORD}\",\"must_change_password\":false}"
  for REPO in flow-backups platform-backups; do
    gitea_api "write access to ${REPO}" PUT \
      "${BASE}/api/v1/repos/${ORG}/${REPO}/collaborators/${GIT_USER}" \
      "{\"permission\":\"write\"}"
  done
fi

echo "Gitea seeded: ${BASE}/${ORG}/{config-backups,flow-backups,platform-backups}"
echo "  flow-backups and platform-backups are writable by Hegemony out of the box:"
echo "  the ${GIT_USER} service account authenticates with the meridian-gitea-token"
echo "  secret as its password. Nothing secret is minted or printed here."
