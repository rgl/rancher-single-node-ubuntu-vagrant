#!/bin/bash
set -eux

dns_server_ip_address="${1:-10.1.0.2}"; shift || true

# change the dns resolver to the mail dns server.
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/dns_servers.conf <<EOF
[Resolve]
DNS=$dns_server_ip_address
EOF
systemctl restart systemd-resolved
cat /etc/hosts
