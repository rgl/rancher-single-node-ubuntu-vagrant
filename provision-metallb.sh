#!/bin/bash
set -eu

#
# deploy the MetalLB LoadBalancer.
# see https://metallb.universe.tf/configuration/#layer-2-configuration

config_metallb_helm_chart_version="${1:-0.12.1}"; shift || true
metallb_ip_addresses="${1:-10.1.0.10-10.1.0.20}"; shift || true

# switch to the System project.
rancher context switch System

# deploy the metallb helm chart.
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
# see https://github.com/helm/charts/tree/master/stable/metallb
# see https://github.com/helm/charts/commits/master/stable/metallb
# see https://github.com/helm/charts/tree/b0f9cb2d7af822e0031f632f2faa0cbb53167770/stable/metallb
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
    cattle-global-data:helm-metallb \
    metallb

echo "waiting for the metallb app to be active..."
rancher wait --timeout=600 metallb

# switch back to the Default project.
rancher context switch Default
