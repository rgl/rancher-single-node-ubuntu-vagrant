#!/bin/bash
set -eux

pandora_ip_address="${1:-10.1.0.2}"; shift || true
pandora_domain="${1:-pandora.rancher.test}"; shift || true

#
# provision the DNS server.
# this will resolve all entries from /etc/hosts by default (like our $pandora_domain).
# NB docker/rancher/coredns/kubernetes inherits resolv.conf from the host.
# see http://www.thekelleys.org.uk/dnsmasq/docs/setup.html
# see http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html

default_dns_resolver=$(systemd-resolve --status | awk '/DNS Servers: /{print $3}') # recurse queries through the default vagrant environment DNS server.
apt-get install -y --no-install-recommends dnsutils dnsmasq
systemctl stop systemd-resolved
systemctl disable systemd-resolved
cat >/etc/dnsmasq.d/local.conf <<EOF
server=$default_dns_resolver
EOF
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
search $(echo -n "$pandora_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')
EOF
systemctl restart dnsmasq

# use it.
cat /etc/hosts
dig $pandora_domain
dig -x $pandora_ip_address
