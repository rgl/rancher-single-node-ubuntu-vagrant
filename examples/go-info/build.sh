#!/bin/bash
set -eux

registry_domain="${1:-pandora.rancher.test}"; shift || true
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'

cd $(dirname $0)

# build the image.
docker build -t go-info:1.0.0 . -f Dockerfile
docker image ls go-info:1.0.0

# push the image to the registry.
docker tag go-info:1.0.0 $registry_host/go-info:1.0.0
docker push $registry_host/go-info:1.0.0

# show the repository (image) details directly from the registry.
# see https://docs.docker.com/registry/spec/api/
# see https://docs.docker.com/registry/spec/manifest-v2-2/
wget -qO- --user "$registry_username" --password "$registry_password" \
    $registry_url/v2/go-info/tags/list | jq .
manifest=$(wget -qO- --user "$registry_username" --password "$registry_password" \
    '--header=Accept: application/vnd.docker.distribution.manifest.v2+json' \
    $registry_url/v2/go-info/manifests/1.0.0)
config_digest=$(echo "$manifest" | jq -r .config.digest)
echo "$manifest" | jq .
wget -qO- --user "$registry_username" --password "$registry_password" \
    $registry_url/v2/go-info/blobs/$config_digest | jq .

# remove it from local cache.
docker image remove go-info:1.0.0
docker image remove $registry_host/go-info:1.0.0

# pull it from the registry.
docker pull $registry_host/go-info:1.0.0

# and remove it again, so we can test it being downloaded by kubernetes.
docker image remove $registry_host/go-info:1.0.0
