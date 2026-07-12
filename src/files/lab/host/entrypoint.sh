#!/bin/sh
# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Start the SSH server and idle. LAN addressing and routes are applied by
# containerlab exec directives in topology.clab.yml after the links exist.
set -e
/usr/sbin/sshd
exec sleep infinity
