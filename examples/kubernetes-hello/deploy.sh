#!/bin/bash
source /vagrant/lib.sh

cd $(dirname $0)

if [ ! -f "tmp/example-resources.yml" ]; then
    mkdir -p tmp
    wget -qO \
        tmp/example-resources.yml \
        https://raw.githubusercontent.com/rgl/kubernetes-hello/master/resources.yml
fi

# NB this will install in the current context (the one returned by rancher
#    context current). if you would want to install it in another project,
#    you would use rancher context switch.
kubectl apply --kustomize .
