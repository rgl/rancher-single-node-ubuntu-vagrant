#!/bin/bash
set -eux

cd $(dirname $0)

echo "deleting the jenkins app..."
rancher app delete jenkins
