#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Render an organization's effective network standards into a run artifact.
# Mounted into the container at /attachments and run as-is; all the org-specific
# values arrive as environment variables the flow resolves from {{ vars.* }} and
# {{ secret(...) }}, so this one script serves the shared, Acme and Globex
# standards flows unchanged.
set -eu

mkdir -p /artifacts/new
REPORT="/artifacts/new/${REPORT_NAME:-standards}.txt"

{
  printf 'Effective network standards\n'
  printf 'Organization : %s\n' "${TENANT_NAME:-unknown}"
  printf 'Curated by   : %s\n' "${STANDARDS_OWNER:-Meridian Shared Standards}"
  printf '  NTP primary    : %s\n' "${NTP_PRIMARY:-<unset>}"
  printf '  DNS primary    : %s\n' "${DNS_PRIMARY:-<unset>}"
  printf '  Syslog primary : %s\n' "${SYSLOG_PRIMARY:-<unset>}"
  if [ -n "${APPROVED_CONTAINER_IMAGES:-}" ]; then
    printf '  Approved images: %s\n' "${APPROVED_CONTAINER_IMAGES}"
  fi
  if [ -n "${MON_TOKEN:-}" ]; then
    printf '  Monitoring token: present (shared, masked)\n'
  fi
} | tee "${REPORT}"
