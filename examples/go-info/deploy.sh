#!/bin/bash
set -eux

cd $(dirname $0)

kubectl apply -f deployment.yml
