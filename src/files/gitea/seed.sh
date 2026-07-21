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
# The two native-write repos need a token: Hegemony authenticates git over HTTP
# with an access token sent as the Basic-auth password (any username). This
# script does NOT mint or print that token — a write credential must not land in
# run/container logs — so, once Gitea is up, create one yourself and store it in
# the meridian-gitea-token secret (see the final instructions below).
# Idempotent — safe to re-run.
set -e

GITEA_CONTAINER="${GITEA_CONTAINER:-meridian-gitea}"
BASE="${GITEA_URL:-http://host.docker.internal:3000}"
ADMIN_USER="${ADMIN_USER:-meridian-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-demo-gitea-admin-password}"
ORG="${GITEA_ORG:-meridian}"

# POST to a Gitea API endpoint, treating a genuine duplicate (409/422) as an
# idempotent success but surfacing auth/network/server failures instead of
# masking them all as "already exists".
gitea_create() {
  desc="$1"
  url="$2"
  data="$3"
  echo "Creating ${desc} (idempotent) ..."
  status=$(curl -sS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X POST "${url}" \
    -H 'Content-Type: application/json' -d "${data}" \
    -o /dev/null -w '%{http_code}') || {
    echo "ERROR: request to create ${desc} failed (network/connection)" >&2
    return 1
  }
  case "${status}" in
    200 | 201) echo "  ${desc}: created." ;;
    409 | 422) echo "  ${desc}: already exists; continuing." ;;
    *)
      echo "ERROR: creating ${desc} returned HTTP ${status}" >&2
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

gitea_create "org ${ORG}" "${BASE}/api/v1/orgs" \
  "{\"username\":\"${ORG}\",\"visibility\":\"public\"}"

for REPO in config-backups flow-backups platform-backups; do
  gitea_create "${REPO} repository" "${BASE}/api/v1/orgs/${ORG}/repos" \
    "{\"name\":\"${REPO}\",\"private\":false,\"auto_init\":true,\"default_branch\":\"main\"}"
done

echo "Gitea seeded: ${BASE}/${ORG}/{config-backups,flow-backups,platform-backups}"
echo "  ------------------------------------------------------------------"
echo "  To let Hegemony write to flow-backups and platform-backups, sign in to"
echo "  Gitea as ${ADMIN_USER}, generate an access token"
echo "  (Settings -> Applications, scope write:repository), and store it in the"
echo "  Hegemony secret 'meridian-gitea-token' (folder"
echo "  orgs/default/secrets/meridian/gitea/token, key 'token'). The token is"
echo "  shown by Gitea only once and never printed here, so it stays out of logs."
echo "  ------------------------------------------------------------------"
