#!/bin/bash
source /vagrant/lib.sh

#
# deploy the MetalLB LoadBalancer.
# see https://metallb.universe.tf/configuration/#layer-2-configuration

config_metallb_helm_chart_version="${1:-2.5.4}"; shift || true
metallb_ip_addresses="${1:-10.10.0.10-10.10.0.20}"; shift || true

# switch to the System project.
rancher context switch "$(cat ~/.rancher-system-project-id)"

# deploy the metallb helm chart.
# see https://github.com/bitnami/charts/tree/master/bitnami/metallb
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
# NB the bitnami rancher app catalog and helm repository was configured in provision/rancher.sh.
echo "deploying the metallb app..."
rancher app install \
    --version $config_metallb_helm_chart_version \
    --namespace metallb-system \
    --values <(cat <<EOF
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - $metallb_ip_addresses
EOF
) \
    cattle-global-data:bitnami-metallb \
    metallb

echo "waiting for the metallb app to be active..."
rancher wait --timeout=600 metallb

# switch back to the Default project.
rancher context switch "$(cat ~/.rancher-default-project-id)"
