#!/bin/bash
set -eu

registry_domain="${1:-pandora.rancher.test}"; shift || true
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_image='registry:2.7.1'
registry_username='vagrant'
registry_password='vagrant'

# copy certificate.
install -d -m 700 /opt/registry
install -d -m 700 /opt/registry/secrets
cp /vagrant/shared/tls/example-ca/$registry_domain-crt.pem /opt/registry/secrets/crt.pem
cp /vagrant/shared/tls/example-ca/$registry_domain-key.pem /opt/registry/secrets/key.pem

# create a registry user.
docker run \
    --rm \
    --entrypoint htpasswd \
    "$registry_image" -Bbn "$registry_username" "$registry_password" >/opt/registry/secrets/htpasswd

# create the http secret.
install -d -m 700 /opt/registry/secrets
echo -n 'http secret' >/opt/registry/secrets/http

# launch the registry.
# see https://docs.docker.com/registry/deploying/
echo "starting registry..."
install -d -m 700 /opt/registry/data
docker run -d \
    --restart=unless-stopped \
    --name registry \
    -p 5000:5000 \
    -v /opt/registry/data:/var/lib/registry \
    -v /opt/registry/secrets:/run/secrets \
    -e REGISTRY_HTTP_SECRET=/run/secrets/http \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/run/secrets/crt.pem \
    -e REGISTRY_HTTP_TLS_KEY=/run/secrets/key.pem \
    -e REGISTRY_AUTH=htpasswd \
    -e 'REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm' \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/run/secrets/htpasswd \
    "$registry_image"

# wait for the registry to be available.
echo "waiting for the registry to become available..."
while ! wget -q --spider --user "$registry_username" --password "$registry_password" "$registry_url/v2/"; do sleep 1; done;

# login into the registry.
echo "logging in the registry..."
docker login $registry_host --username "$registry_username" --password-stdin <<EOF
$registry_password
EOF

# dump the registry configuration.
container_name="registry"
echo "registry version:"
docker exec $container_name registry --version
echo "registry environment variables:"
docker exec $container_name env
echo "registry config:"
docker exec $container_name cat /etc/docker/registry/config.yml
