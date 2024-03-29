#!/bin/bash
source /vagrant/lib.sh

registry_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain:8443"
rancher_ip_address="${1:-10.10.0.3}"; shift || true
admin_password="${1:-admin}"; shift || true
rancher_version="${1:-v2.6.0}"; shift || true
rancher_cli_version="${1:-v2.4.12}"; shift || true
k8s_version="${1:-v1.21.4-rancher1-1}"; shift || true
kubectl_version="${1:-1.21.4}"; shift
krew_version="${1:-v0.4.1}"; shift # NB see https://github.com/kubernetes-sigs/krew
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
kubectl run --restart=Never --image=debian:bullseye-slim -i --rm test -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods
kubectl ingress-nginx --namespace ingress-nginx conf -l app=ingress-nginx
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
# see https://rancher.com/docs/rancher/v2.6/en/installation/other-installation-methods/single-node-docker/
# see https://rancher.com/docs/rancher/v2.6/en/installation/other-installation-methods/single-node-docker/advanced/
echo "starting rancher..."
install -d -m 700 /opt/rancher
install -d -m 700 /opt/rancher/data
install -d -m 700 /opt/rancher/log
install -d -m 700 /opt/rancher/log/audit
docker run -d \
    --restart=unless-stopped \
    --name rancher \
    --privileged \
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
set +x
while [ "$(wget -qO- $rancher_server_url/ping)" != "pong" ]; do sleep 5; done;
set -x
echo "rancher is ready!"

# get the bootstrap password.
bootstrap_password="$(docker logs rancher 2>&1 | perl -n -e '/Bootstrap Password: (.+)/ && print $1')"

# get the admin login token.
echo "getting the admin login token..."
while true; do
    admin_login_token="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --post-data '{"username":"admin","password":"'$bootstrap_password'"}' \
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
    --post-data '{"currentPassword":"'$bootstrap_password'","newPassword":"'$admin_password'"}' \
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
#    NB also use the schemas browser at https://server.rancher.test:8443/v3/schemas.
# NB to troubleshoot why the cluster provisioning is failing with something like:
#       cluster c-fhrlt state: provisioning Failed to get job complete status for job rke-network-plugin-deploy-job in namespace kube-system
#    execute:
#       docker ps -a -f status=exited --format '{{.Names}} {{.Command}}' --no-trunc | grep -v /pause | grep rke-network-plugin
#    then get the logs with, e.g.:
#       docker logs k8s_rke-network-plugin-pod_rke-network-plugin-deploy-job-tcm8p_kube-system_ac5adeb3-16ca-417d-b899-f51f14d5c712_0
# see https://server.rancher.test:8443/v3/schemas/cluster
# see https://server.rancher.test:8443/v3/schemas/rancherKubernetesEngineConfig
# see https://server.rancher.test:8443/v3/schemas/rkeConfigServices
# see https://server.rancher.test:8443/v3/schemas/kubeAPIService
# see https://server.rancher.test:8443/v3/schemas/kubeControllerService
# see https://server.rancher.test:8443/v3/schemas/kubeletService
# see https://rancher.com/docs/rancher/v2.x/en/cluster-provisioning/rke-clusters/windows-clusters/
# see docker ps --format '{{.Image}} {{.Names}} {{.Command}}' --no-trunc
# see docker logs kubelet
# see find /opt -type f | grep -v /catalog-cache
# see /etc/cni
echo "creating the cluster..."
cluster_response="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --post-data '{
        "type": "cluster",
        "name": "example",
        "description": "hello world",
        "dockerRootDir": "/var/lib/docker",
        "enableClusterAlerting": false,
        "enableClusterMonitoring": false,
        "enableNetworkPolicy": false,
        "windowsPreferedCluster": false,
        "rancherKubernetesEngineConfig": {
            "type": "rancherKubernetesEngineConfig",
            "kubernetesVersion": "'$k8s_version'",
            "addonJobTimeout": 45,
            "enableCriDockerd": false,
            "ignoreDockerVersion": true,
            "rotateEncryptionKey": false,
            "sshAgentAuth": false,
            "authentication": {
                "type": "authnConfig",
                "strategy": "x509"
            },
            "dns": {
                "type": "dnsConfig",
                "nodelocal": {
                    "type": "nodelocal",
                    "ip_address": "",
                    "node_selector": null,
                    "update_strategy": {}
                }
            },
            "network": {
                "type": "networkConfig",
                "mtu": 0,
                "plugin": "flannel",
                "options": {
                    "flannel_backend_type": "host-gw",
                    "flannel_iface": "eth1"
                }
            },
            "ingress": {
                "type": "ingressConfig",
                "provider": "nginx",
                "defaultBackend": false,
                "httpPort": 0,
                "httpsPort": 0
            },
            "monitoring": {
                "type": "monitoringConfig",
                "provider": "metrics-server",
                "replicas": 1
            },
            "services": {
                "type": "rkeConfigServices",
                "kubeApi": {
                    "type": "kubeAPIService",
                    "alwaysPullImages": false,
                    "podSecurityPolicy": false,
                    "serviceClusterIpRange": "10.53.0.0/16",
                    "serviceNodePortRange": "30000-32767",
                    "secretsEncryptionConfig": {
                        "enabled": false,
                        "type": "secretsEncryptionConfig"
                    }
                },
                "kubeController": {
                    "type": "kubeControllerService",
                    "clusterCidr": "10.52.0.0/16",
                    "serviceClusterIpRange": "10.53.0.0/16"
                },
                "kubelet": {
                    "type": "kubeletService",
                    "clusterDnsServer": "10.53.0.10",
                    "clusterDomain": "cluster.domain"
                },
                "etcd": {
                    "creation": "12h",
                    "extraArgs": {
                        "heartbeat-interval": 500,
                        "election-timeout": 5000
                    },
                    "gid": 0,
                    "retention": "72h",
                    "snapshot": false,
                    "uid": 0,
                    "type": "etcdService",
                    "backupConfig": {
                        "type": "backupConfig",
                        "enabled": true,
                        "intervalHours": 12,
                        "retention": 6,
                        "safeTimestamp": false,
                        "timeout": 300
                    }
                }
            },
            "upgradeStrategy": {
                "maxUnavailableControlplane": "1",
                "maxUnavailableWorker": "10%",
                "drain": "false",
                "nodeDrainInput": {
                    "deleteLocalData": false,
                    "force": false,
                    "gracePeriod": -1,
                    "ignoreDaemonSets": true,
                    "timeout": 120,
                    "type": "nodeDrainInput"
                },
                "maxUnavailableUnit": "percentage"
            }
        },
        "localClusterAuthEndpoint": {
            "enabled": true,
            "type": "localClusterAuthEndpoint"
        },
        "labels": {},
        "annotations": {},
        "agentEnvVars": [],
        "scheduledClusterScan": {
            "enabled": false,
            "scheduleConfig": null,
            "scanConfig": null
        }
    }' \
    "$rancher_server_url/v3/cluster")"

# register this node as a rancher-agent.
echo "getting the rancher-agent registration command..."
cluster_id="$(jq -r .id <<<"$cluster_response")"
while true; do
    cluster_registration_token_response="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $admin_api_token" \
            --post-data '{"type":"clusterRegistrationToken","clusterId":"'$cluster_id'"}' \
            "$rancher_server_url/v3/clusterregistrationtoken" || true)"
    [ -n "$cluster_registration_token_response" ] && break || sleep 5
done
cluster_registration_token_url="$(jq -r .links.self <<<"$cluster_registration_token_response")"
cluster_registration_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        "$cluster_registration_token_url")"
rancher_agent_registration_command="
    $(jq -r .nodeCommand <<<"$cluster_registration_response")
        --address $node_ip_address
        --internal-address $node_ip_address
        --etcd
        --controlplane
        --worker"
echo "registering this node as a rancher-agent with $rancher_agent_registration_command..."
$rancher_agent_registration_command

# wait for the cluster to be active.
# NB this can only complete after the rancher-agent (with the etcd and controlplane roles) is up.
echo "waiting for cluster $cluster_id to be active..."
set +x
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
set -x

# save kubeconfig.
echo "saving ~/.kube/config..."
kubeconfig_response="$(
    wget -qO- \
        --method POST \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/clusters/$cluster_id?action=generateKubeconfig")"
install -d -m 700 ~/.kube
install -m 600 /dev/null ~/.kube/config
echo "$kubeconfig_response" | jq -r .config >~/.kube/config
# also save the kubectl configuration on the host, so we can access it there.
cp ~/.kube/config /vagrant/shared/admin.conf

# see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
wget -qO /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' >/etc/apt/sources.list.d/kubernetes.list
apt-get update
kubectl_package_version="$(apt-cache madison kubectl | awk "/$kubectl_version-/{print \$3}")"
apt-get install -y "kubectl=$kubectl_package_version"

# install the bash completion script.
kubectl completion bash >/etc/bash_completion.d/kubectl

# install the krew kubectl package manager.
echo "installing the krew $krew_version kubectl package manager..."
wget -qO- "https://github.com/kubernetes-sigs/krew/releases/download/$krew_version/krew.tar.gz" | tar xzf - ./krew-linux_amd64
wget -q "https://github.com/kubernetes-sigs/krew/releases/download/$krew_version/krew.yaml"
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

echo "getting the $cluster_id cluster System project..."
project_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/projects?clusterId=$cluster_id&name=System")"
system_project_id="$(echo "$project_response" | jq -r .data[].id)"
echo -n "$system_project_id" >~/.rancher-system-project-id

echo "getting the $cluster_id cluster Default project..."
project_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/projects?clusterId=$cluster_id&name=Default")"
default_project_id="$(echo "$project_response" | jq -r .data[].id)"
echo -n "$default_project_id" >~/.rancher-default-project-id

# login into rancher.
echo "login into rancher cli..."
rancher login "$rancher_server_url" \
    --token "$admin_api_token" \
    --name 'example' \
    --context "$default_project_id"

# register custom registry for all namespaces inside the created cluster Default project.
echo "registering the $registry_host registry..."
registry_name="$(echo "$registry_host" | sed -E 's,[^a-z0-9],-,g')"
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

# enable the nfs-subdir-external-provisioner app catalog.
# see https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
echo 'enabling the nfs-subdir-external-provisioner app catalog...'
rancher catalog add --helm-version helm_v3 nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
echo 'waiting for the nfs-subdir-external-provisioner app catalog to be active...'
rancher catalog refresh --wait --wait-timeout=0 nfs-subdir-external-provisioner

# enable the bitnami app catalog.
# NB we must really use helm_v3 instead of v3.
#    see https://github.com/rancher/rancher/issues/29079
echo 'enabling the Bitnami app catalog...'
rancher catalog add --helm-version helm_v3 bitnami https://charts.bitnami.com/bitnami
echo 'waiting for the Bitnami app catalog to be active...'
rancher catalog refresh --wait --wait-timeout=0 bitnami
