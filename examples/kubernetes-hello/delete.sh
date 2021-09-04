#!/bin/bash
source /vagrant/lib.sh

cd $(dirname $0)

kubectl delete --kustomize .
