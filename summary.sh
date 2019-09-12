#!/bin/bash
set -eux

registry_domain="${1:-pandora.rancher.test}"; shift || true
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"

# wrap commands in a way that their output is correctly (most of the time) displayed on the vagrant up output.
# see https://github.com/hashicorp/vagrant/issues/11047
function docker {
    set +x; echo "$(/usr/bin/docker "$@")"; set -x
}
function kubectl {
    set +x; echo "$(/usr/bin/kubectl "$@")"; set -x
}

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
kubectl api-versions
kubectl api-resources -o wide
#kubectl get nodes -o wide
#kubectl get pods --all-namespaces
kubectl get all --all-namespaces

# really get all objects.
# see https://github.com/corneliusweig/ketall/blob/master/doc/USAGE.md
kubectl krew install get-all
kubectl get-all

# kubernetes contexts.
# NB the example context gives you indirect access to the rke cluster api-server endpoint (e.g. https://server.rancher.test:8443/k8s/clusters/c-g5282).
# NB the example-server context gives you direct access to the rke cluster api-server endpoint (e.g. https://10.1.0.3:6443).
kubectl config get-contexts

# show the kubernetes system arguments.
docker inspect kube-apiserver | jq -r '.[0].Args[]' | sed -E 's,(.+),    \1,g'
docker inspect kube-scheduler | jq -r '.[0].Args[]' | sed -E 's,(.+),    \1,g'
docker inspect kube-controller-manager | jq -r '.[0].Args[]' | sed -E 's,(.+),    \1,g'
docker inspect kubelet | jq -r '.[0].Args[]' | sed -E 's,(.+),    \1,g'

# rbac info.
kubectl auth can-i --list
kubectl get serviceaccount --all-namespaces
kubectl get role --all-namespaces
kubectl get rolebinding --all-namespaces
kubectl get rolebinding --all-namespaces -o json | jq .items[].subjects
kubectl get clusterrole --all-namespaces
kubectl get clusterrolebinding --all-namespaces

# rbac access matrix.
# see https://github.com/corneliusweig/rakkess/blob/master/doc/USAGE.md
kubectl krew install access-matrix
kubectl access-matrix version --full
kubectl access-matrix # at cluster scope.
kubectl access-matrix --namespace default
kubectl access-matrix --sa example-go-info --namespace default

# show dns information.
# see https://rancher.com/docs/rancher/v2.x/en/troubleshooting/dns/
kubectl -n kube-system get svc -l k8s-app=kube-dns
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup kubernetes.default
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup $registry_domain
kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup ruilopes.com
