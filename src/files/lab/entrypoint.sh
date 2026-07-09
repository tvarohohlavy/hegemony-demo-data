#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Start the SSH server, then hand off to FRR's normal container entrypoint so
# zebra/ospfd come up exactly as in the stock image.
set -e
/usr/sbin/sshd
exec /sbin/tini -- /usr/lib/frr/docker-start
