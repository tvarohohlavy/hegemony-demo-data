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
#   * platform-backups — a Platform Sync BACKUP profile exports platform config
#                        here (created in the UI; see docs/walkthrough.md).
# The two native-write repos need a token: Hegemony authenticates git over HTTP
# with an access token sent as the Basic-auth password (any username), which
# this script mints and prints for you to paste into the meridian-gitea-token
# secret. Idempotent — safe to re-run.
set -e

GITEA_CONTAINER="${GITEA_CONTAINER:-meridian-gitea}"
BASE="${GITEA_URL:-http://host.docker.internal:3000}"
ADMIN_USER="${ADMIN_USER:-meridian-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-demo-gitea-admin-password}"
ORG="${GITEA_ORG:-meridian}"

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

echo "Creating public org ${ORG} (idempotent) ..."
curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X POST "${BASE}/api/v1/orgs" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${ORG}\",\"visibility\":\"public\"}" \
  || echo "org already exists; continuing"

for REPO in config-backups flow-backups platform-backups; do
  echo "Creating ${REPO} repository (idempotent) ..."
  curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X POST "${BASE}/api/v1/orgs/${ORG}/repos" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${REPO}\",\"private\":false,\"auto_init\":true,\"default_branch\":\"main\"}" \
    || echo "repository ${REPO} already exists; continuing"
done

# Mint a write-scoped access token for Hegemony's native git integrations
# (flow Git-sync and Platform Sync). Gitea validates a token supplied as the
# Basic-auth password regardless of the username, which is exactly how
# Hegemony's auth_secret_ref sends it (Authorization: Basic base64(x-access-token:TOKEN)).
# Token names are unique per user, so a re-run reports the existing one instead
# of failing the whole seed.
echo "Minting the 'hegemony-backups' access token (idempotent) ..."
TOKEN_JSON=$(curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X POST \
  "${BASE}/api/v1/users/${ADMIN_USER}/tokens" \
  -H 'Content-Type: application/json' \
  -d '{"name":"hegemony-backups","scopes":["write:repository"]}' 2>/dev/null || true)
TOKEN=$(printf '%s' "${TOKEN_JSON}" | sed -n 's/.*"sha1":"\([^"]*\)".*/\1/p')
if [ -n "${TOKEN}" ]; then
  echo "  ------------------------------------------------------------------"
  echo "  Store this token in the Hegemony secret 'meridian-gitea-token'"
  echo "  (folder orgs/default/secrets/meridian/gitea/token, key 'token') so"
  echo "  the flow-backups and platform-backups repositories can be written to:"
  echo "    ${TOKEN}"
  echo "  ------------------------------------------------------------------"
else
  echo "  Token 'hegemony-backups' already exists; reuse the value already stored"
  echo "  in the meridian-gitea-token secret, or delete the token in Gitea and"
  echo "  re-run this flow to mint a fresh one."
fi

echo "Gitea seeded: ${BASE}/${ORG}/{config-backups,flow-backups,platform-backups}"
