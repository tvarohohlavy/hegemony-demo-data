#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Install ansible-core into the throwaway alpine container and run the golden
# config-audit playbook against localhost. Kept in a mounted file so the flow
# step carries no inline script; all inputs arrive as environment variables.
set -eu

apk add --no-cache ansible-core >/dev/null
mkdir -p /artifacts/new
ansible-playbook -i 'localhost,' -c local /attachments/audit.yml
