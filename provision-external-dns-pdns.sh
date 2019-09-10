#!/bin/bash
set -eu

pdns_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_domain="$(echo -n "$rancher_server_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"

# install the PowerDNS external-dns provider.
# see https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/pdns.md
# see https://github.com/kubernetes-incubator/external-dns/blob/master/docs/initial-design.md
external_dns_namespace='default'
kubectl apply --namespace "$external_dns_namespace" -f - <<EOF
$(
    cat /vagrant/external-dns-pdns.yaml \
        | sed -E "s,@@namespace@@,$external_dns_namespace,g" \
        | sed -E "s,@@pdns-server@@,http://$pdns_domain:8081,g" \
        | sed -E "s,@@pdns-api-key@@,vagrant,g" \
        | sed -E "s,@@txt-owner-id@@,vagrant,g" \
        | sed -E "s,@@domain-filter@@,$rancher_domain,g"
)
EOF
