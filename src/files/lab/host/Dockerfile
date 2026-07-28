# SPDX-FileCopyrightText: 2025-2026 Jakub Trávník <jakub.travnik@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Lightweight Linux endpoint for the Meridian lab: an Alpine host with sshd so
# Hegemony's shell.execute handler can log in like to any server, plus
# iproute2/iputils for end-to-end reachability tests across the routed fabric.
# ping gets cap_net_raw so the non-root login can run it.
#
# python3 + password-gated sudo make the host a first-class Ansible managed
# node for the "IaC: Ansible server baseline rollout" flow: ansible modules
# need a python interpreter on the target, and the baseline playbook escalates
# with become (using the vault-sourced login password) to write under /etc —
# the same shape as a real server fleet's automation account.
#
# Built locally by "Lab: Provision and tear down demo datacenter" and
# referenced from topology.clab.yml as image "meridian/lab-host:latest".
FROM alpine:3.22

# The login password is injected at build time from the meridian-lab-ssh vault
# secret (same credential the git inventory provider hands to the routers).
ARG LAB_PASSWORD=demo-lab-password

RUN apk add --no-cache openssh iproute2 iputils libcap-utils python3 sudo \
    && ssh-keygen -A \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && adduser -D -s /bin/sh clab \
    && echo "clab:${LAB_PASSWORD}" | chpasswd \
    && echo "clab ALL=(ALL) ALL" > /etc/sudoers.d/clab \
    && chmod 0440 /etc/sudoers.d/clab \
    && setcap cap_net_raw+ep "$(command -v ping)"

COPY entrypoint.sh /usr/local/bin/host-entrypoint.sh
RUN chmod +x /usr/local/bin/host-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/host-entrypoint.sh"]
