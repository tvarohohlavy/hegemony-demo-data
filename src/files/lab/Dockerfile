# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# FRRouting + OpenSSH lab node. The stock FRR image has no SSH server, so
# Hegemony's network CLI step handlers (netmiko over the device access config)
# cannot reach it. This image adds sshd and a non-root "clab" login whose login
# SHELL IS vtysh: an SSH session drops straight into FRR's Cisco-IOS-style CLI,
# so Hegemony's netcli handlers (platform ios-xe -> netmiko cisco_ios) drive it
# exactly like a real switch. clab is a member of the frr/frrvty groups so vtysh
# can reach the daemon sockets.
#
# Built locally by "Lab: Bootstrap demo datacenter" and referenced from
# topology.clab.yml as image "meridian/frr-lab:latest".
FROM quay.io/frrouting/frr:9.1.0

# openssh for the SSH channel; shadow for chpasswd.
RUN apk add --no-cache openssh openssh-server shadow \
    && ssh-keygen -A \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && adduser -D -s /usr/bin/vtysh clab \
    && addgroup clab frr \
    && addgroup clab frrvty \
    && echo "clab:demo-lab-password" | chpasswd

COPY entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
