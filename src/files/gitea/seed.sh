#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Provision the demo Gitea so the config-backup flow has somewhere to push:
# wait for health, create the admin account, then create a public org and an
# auto-initialised config-backups repository. Idempotent — safe to re-run.
set -e

GITEA_CONTAINER="${GITEA_CONTAINER:-meridian-gitea}"
BASE="${GITEA_URL:-http://host.docker.internal:3000}"
ADMIN_USER="${ADMIN_USER:-meridian-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-demo-gitea-admin-password}"
ORG="${GITEA_ORG:-meridian}"

echo "Waiting for Gitea at ${BASE} ..."
for _ in $(seq 1 60); do
  if curl -fsS "${BASE}/api/healthz" >/dev/null 2>&1; then
    echo "Gitea is healthy."
    break
  fi
  sleep 2
done

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

echo "Creating config-backups repository (idempotent) ..."
curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -X POST "${BASE}/api/v1/orgs/${ORG}/repos" \
  -H 'Content-Type: application/json' \
  -d '{"name":"config-backups","private":false,"auto_init":true,"default_branch":"main"}' \
  || echo "repository already exists; continuing"

echo "Gitea seeded: ${BASE}/${ORG}/config-backups"
