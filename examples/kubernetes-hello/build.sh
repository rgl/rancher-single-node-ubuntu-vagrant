#!/bin/bash
set -eux

registry_domain="${1:-pandora.rancher.test}"; shift || true
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'

cd $(dirname $0)

# pull image from docker hub and tag it with a local tag.
# see https://hub.docker.com/repository/docker/ruilopes/kubernetes-hello
# see https://github.com/rgl/kubernetes-hello
docker_hub_kubernetes_hello_image='ruilopes/kubernetes-hello:v0.0.0.202004041457-test'
docker pull $docker_hub_kubernetes_hello_image
docker tag $docker_hub_kubernetes_hello_image $registry_host/kubernetes-hello:1.0.0
docker image remove $docker_hub_kubernetes_hello_image

# push the image to our registry.
docker push $registry_host/kubernetes-hello:1.0.0

# show the repository (image) details directly from the registry.
# see https://docs.docker.com/registry/spec/api/
# see https://docs.docker.com/registry/spec/manifest-v2-2/
wget -qO- --user "$registry_username" --password "$registry_password" \
    $registry_url/v2/kubernetes-hello/tags/list | jq .
manifest=$(wget -qO- --user "$registry_username" --password "$registry_password" \
    '--header=Accept: application/vnd.docker.distribution.manifest.v2+json' \
    $registry_url/v2/kubernetes-hello/manifests/1.0.0)
config_digest=$(jq -r .config.digest <<<"$manifest")
jq . <<<"$manifest"
wget -qO- --user "$registry_username" --password "$registry_password" \
    $registry_url/v2/kubernetes-hello/blobs/$config_digest | jq .

# remove it from local cache.
docker image remove $registry_host/kubernetes-hello:1.0.0

# pull it from the registry.
docker pull $registry_host/kubernetes-hello:1.0.0

# and remove it again, so we can test it being downloaded by kubernetes.
docker image remove $registry_host/kubernetes-hello:1.0.0
