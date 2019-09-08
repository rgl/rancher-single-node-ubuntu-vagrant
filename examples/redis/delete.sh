#!/bin/bash
set -eux

cd $(dirname $0)

echo "deleting the redis app..."
rancher app delete redis
