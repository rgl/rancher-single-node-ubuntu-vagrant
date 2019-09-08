#!/bin/bash
set -eux

cd $(dirname $0)

kubectl delete -f deployment.yml
