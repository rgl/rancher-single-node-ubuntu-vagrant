#!/bin/bash
set -eux

cd $(dirname $0)

if [ ! -f "tmp/example-resources.yml" ]; then
    mkdir -p tmp
    wget -qO \
        tmp/example-resources.yml \
        https://raw.githubusercontent.com/rgl/kubernetes-hello/master/resources.yml
fi

kubectl apply --kustomize .
