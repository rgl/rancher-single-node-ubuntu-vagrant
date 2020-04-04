#!/bin/bash
set -eux

redis_helm_version="${1:-10.5.7}"; shift || true # see https://github.com/helm/charts/blob/master/stable/redis/Chart.yaml

cd $(dirname $0)

# deploy the redis helm chart.
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
# see https://github.com/helm/charts/tree/master/stable/redis
# see https://github.com/helm/charts/commits/master/stable/redis
# see https://github.com/helm/charts/tree/c3fad1026ce72c922a61eb02485c25fb0eca0940/stable/redis
echo "deploying the redis app..."
rancher app install \
    --version $redis_helm_version \
    --set "master.persistence.storageClass=nfs-client" \
    --set "master.persistence.size=1Gi" \
    --set "cluster.enabled=false" \
    --namespace redis \
    cattle-global-data:helm-redis \
    redis

echo "waiting for the redis app to be active..."
rancher wait --timeout=600 redis

echo "getting the redis image and password..."
redis_image="$(kubectl get pod --namespace redis redis-master-0 -o jsonpath="{.spec.containers[?(@.name=='redis')].image}")"
redis_password="$(kubectl get secret --namespace redis redis -o jsonpath="{.data.redis-password}" | base64 --decode)"

echo "waiting for redis to be ready..."
kubectl run \
    --namespace redis \
    --rm -i --restart=Never \
    --image "$redis_image" \
    --env "REDISCLI_AUTH=$redis_password" \
    redis-client \
    --command sh -- -c 'while [ "$(redis-cli -h redis-master ping)" != "PONG" ]; do sleep 1; done; echo "redis is ready!"'

echo "trying redis master..."
kubectl run \
    --namespace redis \
    --rm -i --restart=Never \
    --image "$redis_image" \
    --env "REDISCLI_AUTH=$redis_password" \
    redis-client \
    --command redis-cli -- -h redis-master INFO

echo "setting the message key value..."
kubectl run \
    --namespace redis \
    --rm -i --restart=Never \
    --image "$redis_image" \
    --env "REDISCLI_AUTH=$redis_password" \
    redis-client \
    --command redis-cli -- -h redis-master SET message 'Hello World!'
