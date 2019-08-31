#!/bin/bash
set -eux

registry_domain="${1:-pandora.rancher.test}"; shift || true
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"

# list images.
echo "listing $registry_host images..."
wget -qO- --user vagrant --password vagrant \
    "$registry_url/v2/_catalog" \
    | jq .

echo "listing local images..."
docker image ls | tail +2 | grep -v '<none>' | sort

# docker info.
docker version
docker info
docker ps --format '{{.Image}} {{.Names}}' | grep -v '/pause' | sort

# kubernetes info.
kubectl version --short
kubectl cluster-info
#kubectl get nodes -o wide
#kubectl get pods --all-namespaces
kubectl get all --all-namespaces

# rbac info.
kubectl get serviceaccount --all-namespaces
kubectl get role --all-namespaces
kubectl get rolebinding --all-namespaces
kubectl get rolebinding --all-namespaces -o json | jq .items[].subjects
kubectl get clusterrole --all-namespaces
kubectl get clusterrolebinding --all-namespaces

# show dns information.
# see https://rancher.com/docs/rancher/v2.x/en/troubleshooting/dns/
kubectl -n kube-system get svc -l k8s-app=kube-dns
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup kubernetes.default
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup $registry_domain
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup ruilopes.com
