#!/bin/bash
set -eu

registry_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain:8443"
rancher_ip_address="${1:-10.1.0.3}"; shift || true
admin_password="${1:-admin}"; shift || true
rancher_version="${1:-v2.2.8}"; shift || true
rancher_cli_version="${1:-v2.2.0}"; shift || true
k8s_version="${1:-v1.15.3-rancher1-1}"; shift || true
kubectl_version="${1:-1.15.3-00}"; shift # NB execute apt-cache madison kubectl to known the available versions.
krew_version="${1:-v0.2.1}"; shift # NB see https://github.com/kubernetes-sigs/krew
rancher_domain="$(echo -n "$registry_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"
node_ip_address="$rancher_ip_address"
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'

# add useful commands to the bash history.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
# see https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
cat >~/.bash_history <<'EOF'
cat /etc/resolv.conf
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf
kubectl run --generator=run-pod/v1 --restart=Never --image=debian:buster-slim -it --rm test cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods
# NB the backends, general, certs, and conf subcommands require ingress-nginx
#    0.23.0+ BUT rancher 2.2.8 ships with 0.21.0.
kubectl ingress-nginx lint --show-all --all-namespaces
kubectl ingress-nginx ingresses --all-namespaces
EOF

# copy certificate.
install -d -m 700 /opt/rancher/ssl
cp /vagrant/shared/tls/example-ca/example-ca-crt.pem /opt/rancher/ssl/cacerts.pem
cp /vagrant/shared/tls/example-ca/$rancher_server_domain-crt.pem /opt/rancher/ssl/cert.pem
cp /vagrant/shared/tls/example-ca/$rancher_server_domain-key.pem /opt/rancher/ssl/key.pem

# launch rancher.
# NB because we are launching rancher-agent with all roles we need to use
#    non-standard ports for rancher server because the standard ones will
#    be used by the ingress controller.
echo "starting rancher..."
install -d -m 700 /opt/rancher
install -d -m 700 /opt/rancher/data
install -d -m 700 /opt/rancher/log
install -d -m 700 /opt/rancher/log/audit
docker run -d \
    --restart=unless-stopped \
    --name rancher \
    -p 8080:80 \
    -p 8443:443 \
    -v /opt/rancher/data:/var/lib/rancher \
    -v /opt/rancher/ssl/cert.pem:/etc/rancher/ssl/cert.pem:ro \
    -v /opt/rancher/ssl/key.pem:/etc/rancher/ssl/key.pem:ro \
    -v /opt/rancher/ssl/cacerts.pem:/etc/rancher/ssl/cacerts.pem:ro \
    -e AUDIT_LEVEL=3 \
    -v /opt/rancher/log/audit:/var/log/auditlog \
    "rancher/rancher:${rancher_version}"

# wait for it to be ready.
echo "waiting for rancher to be ready..."
while [ "$(wget -qO- $rancher_server_url/ping)" != "pong" ]; do sleep 5; done;
echo "rancher is ready!"

# get the admin login token.
echo "getting the admin login token..."
while true; do
    admin_login_token="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --post-data '{"username":"admin","password":"admin"}' \
            "$rancher_server_url/v3-public/localProviders/local?action=login" \
        | jq -r .token)"
    [ "$admin_login_token" != 'null' ] && [ "$admin_login_token" != '' ] && break
    sleep 5
done

# set the admin password.
echo "setting the admin password..."
wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_login_token" \
    --post-data '{"currentPassword":"admin","newPassword":"'$admin_password'"}' \
    "$rancher_server_url/v3/users?action=changepassword"

# create the api token.
echo "creating the admin api token..."
admin_api_token="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_login_token" \
        --post-data '{"type":"token","description":"automation"}' \
        "$rancher_server_url/v3/token" \
    | jq -r .token)"
echo -n "$admin_api_token" >~/.rancher-admin-api-token
chmod 400 ~/.rancher-admin-api-token

# set the server-url.
echo "setting the rancher server-url setting..."
wget -qO- \
    --method PUT \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --body-data '{"name":"server-url","value":"'$rancher_server_url'"}' \
    "$rancher_server_url/v3/settings/server-url"

# set the telemetry-opt.
echo "setting the rancher telemetry-opt setting..."
wget -qO- \
    --method PUT \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --body-data '{"name":"telemetry-opt","value":"out"}' \
    "$rancher_server_url/v3/settings/telemetry-opt"

# create the cluster.
# NB this JSON can be obtained by observing the network when manually creating a cluster from the rancher UI.
echo "creating the cluster..."
cluster_response="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --post-data '{
        "dockerRootDir": "/var/lib/docker",
        "enableNetworkPolicy": false,
        "type": "cluster",
        "rancherKubernetesEngineConfig": {
            "kubernetesVersion": "'$k8s_version'",
            "addonJobTimeout": 30,
            "ignoreDockerVersion": true,
            "sshAgentAuth": false,
            "type": "rancherKubernetesEngineConfig",
            "authentication": {
                "type": "authnConfig",
                "strategy": "x509"
            },
            "network": {
                "options": {
                    "flannelBackendType": "vxlan"
                },
                "plugin": "canal",
                "canalNetworkProvider": {
                    "iface": "eth1"
                }
            },
            "ingress": {
                "type": "ingressConfig",
                "provider": "nginx"
            },
            "monitoring": {
                "type": "monitoringConfig",
                "provider": "metrics-server"
            },
            "services": {
                "type": "rkeConfigServices",
                "kubeApi": {
                    "podSecurityPolicy": false,
                    "type": "kubeAPIService"
                },
                "etcd": {
                    "creation": "12h",
                    "extraArgs": {
                        "heartbeat-interval": 500,
                        "election-timeout": 5000
                    },
                    "retention": "72h",
                    "snapshot": false,
                    "type": "etcdService",
                    "backupConfig": {
                        "enabled": true,
                        "intervalHours": 12,
                        "retention": 6,
                        "type": "backupConfig"
                    }
                }
            }
        },
        "localClusterAuthEndpoint": {
            "enabled": true,
            "type": "localClusterAuthEndpoint"
        },
        "name": "example",
        "description": "hello world"
    }' \
    "$rancher_server_url/v3/cluster")"

# register this node as a rancher-agent.
echo "getting the rancher-agent registration command..."
cluster_id="$(echo "$cluster_response" | jq -r .id)"
cluster_registration_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        --post-data '{"type":"clusterRegistrationToken","clusterId":"'$cluster_id'"}' \
        "$rancher_server_url/v3/clusterregistrationtoken")"
echo "registering this node as a rancher-agent..."
rancher_agent_registration_command="
    $(echo "$cluster_registration_response" | jq -r .nodeCommand)
        --address $node_ip_address
        --internal-address $node_ip_address
        --etcd
        --controlplane
        --worker"
$rancher_agent_registration_command

# wait for the cluster to be active.
# NB this can only complete after the rancher-agent (with the etcd and controlplane roles) is up.
echo "waiting for cluster $cluster_id to be active..."
previous_message=""
while true; do
    cluster_response="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $admin_api_token" \
            "$rancher_server_url/v3/cluster/$cluster_id")"
    cluster_state="$(echo "$cluster_response" | jq -r .state)"
    cluster_transitioning_message="$(echo "$cluster_response" | jq -r .transitioningMessage)"
    message="cluster $cluster_id state: $cluster_state $cluster_transitioning_message"
    if [ "$message" != "$previous_message" ]; then
        previous_message="$message"
        echo "$message"
    fi
    [ "$cluster_state" = 'active' ] && break
    sleep .5
done

# save kubeconfig.
echo "saving ~/.kube/config..."
kubeconfig_response="$(
    wget -qO- \
        --method POST \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/clusters/$cluster_id?action=generateKubeconfig")"
install -d -m 700 ~/.kube
echo "$kubeconfig_response" | jq -r .config >~/.kube/config
# also save the kubectl configuration on the host, so we can access it there.
cp ~/.kube/config /vagrant/shared/admin.conf

# install kubectl.
echo "installing kubectl $kubectl_version..."
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y "kubectl=$kubectl_version"

# install the bash completion script.
kubectl completion bash >/etc/bash_completion.d/kubectl

# install the krew kubectl package manager.
echo "installing the krew $krew_version kubectl package manager..."
wget -qO- "https://storage.googleapis.com/krew/$krew_version/krew.tar.gz" | tar xzf - ./krew-linux_amd64
wget -q "https://storage.googleapis.com/krew/$krew_version/krew.yaml"
./krew-linux_amd64 install --manifest=krew.yaml
cat >/etc/profile.d/krew.sh <<'EOF'
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
EOF
source /etc/profile.d/krew.sh
kubectl krew version

# install the ingress-nginx kubectl plugin.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
echo "install the kubectl ingress-nginx plugin..."
kubectl krew install ingress-nginx

# install the rancher cli.
echo "installing rancher cli..."
wget -qO- "https://github.com/rancher/cli/releases/download/$rancher_cli_version/rancher-linux-amd64-$rancher_cli_version.tar.xz" \
    | tar xJf - --strip-components 2
mv rancher /usr/local/bin
rancher login "$rancher_server_url" --token "$admin_api_token" --name 'example'

# register custom registry for all namespaces inside the created cluster Default project.
registry_name="$(echo "$registry_host" | sed -E 's,[^a-z0-9],-,g')"
echo "getting the $cluster_id cluster Default project..."
project_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/projects?clusterId=$cluster_id&name=Default")"
echo "registering the $registry_host registry..."
docker_credentials_url="$(echo "$project_response" | jq -r .data[].links.dockerCredentials)"
docker_credentials_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        --post-data '{"type":"dockerCredential","registries":{"'$registry_host'":{"username":"'$registry_username'","password":"'$registry_password'"}},"name":"'$registry_name'"}' \
        "$docker_credentials_url")"

# add the custom registry to the default service account.
# see https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
# NB without this you need to explicitly add imagePullSecrets to your pod definitions, e.g.:
#       apiVersion: apps/v1
#       kind: Pod
#       spec:
#           imagePullSecrets:
#               - name: pandora-rancher-test-5000
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"'$registry_name'"}]}'
#kubectl get serviceaccount default -o yaml

# login into the registry.
echo "logging in the registry..."
docker login $registry_host --username "$registry_username" --password-stdin <<EOF
$registry_password
EOF

# enable the helm stable app catalog.
echo 'enabling the Helm Stable app catalog...'
rancher catalog add --branch master helm https://kubernetes-charts.storage.googleapis.com/

echo 'waiting for the Helm Stable app catalog to be active...'
rancher catalog refresh --wait --wait-timeout=0 helm
