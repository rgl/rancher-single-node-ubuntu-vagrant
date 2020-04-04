#!/bin/bash
set -eu

#
# deploy the nfs-client-provisioner persistent NFS volume provider.
# see https://github.com/kubernetes-incubator/external-storage/tree/master/nfs

nfs_server="${1:-pandora.rancher.test}"; shift || true
nfs_path='/var/nfs'
nfs_client_provisioner_version="${1:-1.2.8}"; shift || true

# switch to the System project.
rancher context switch System

# deploy the nfs-client-provisioner helm chart.
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
echo "deploying the nfs-client-provisioner app..."
rancher app install \
    --version $nfs_client_provisioner_version \
    --set "nfs.server=$nfs_server" \
    --set "nfs.path=$nfs_path" \
    --namespace nfs-client-provisioner-system \
    cattle-global-data:helm-nfs-client-provisioner \
    nfs-client-provisioner

echo "waiting for the nfs-client-provisioner app to be active..."
rancher wait --timeout=600 nfs-client-provisioner

# switch back to the Default project.
rancher context switch Default
