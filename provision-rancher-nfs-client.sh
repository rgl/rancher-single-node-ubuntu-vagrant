#!/bin/bash
set -eu

#
# deploy the nfs-client-provisioner persistent NFS volume provider.
# see https://github.com/kubernetes-incubator/external-storage/tree/master/nfs

rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain:8443"
nfs_server="${1:-pandora.rancher.test}"; shift || true
nfs_path='/var/nfs'
nfs_client_provisioner_version="${1:-1.2.6}"; shift || true
admin_api_token="$(cat ~/.rancher-admin-api-token)"
cluster_name='example'
project_name='Default'

# find the cluster id.
cluster_id="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    "$rancher_server_url/v3/clusters/?name=$cluster_name" \
    | jq -r '.data[].id')"

# find the project id.
project_id="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    "$rancher_server_url/v3/clusters/$cluster_id/projects/?name=$project_name" \
    | jq -r '.data[].id')"

# create the namespace.
# NB this JSON can be obtained by observing the network when manually creating the object from the rancher UI.
echo "creating the nfs-client-provisioner namespace..."
namespace_response="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --post-data '{
        "type": "namespace",
        "name": "nfs-client-provisioner",
        "projectId": "'$project_id'"
    }' \
    "$rancher_server_url/v3/clusters/$cluster_id/namespace")"
namespace_id="$(echo "$namespace_response" | jq -r '.id')"

# wait for the namespace to be active.
echo "waiting for nfs-client-provisioner namespace to be active..."
previous_message=""
while true; do
    namespace_response="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $admin_api_token" \
            "$rancher_server_url/v3/clusters/$cluster_id/namespaces/$namespace_id")"
    namespace_state="$(echo "$namespace_response" | jq -r .state)"
    namespace_transitioning_message="$(echo "$namespace_response" | jq -r .transitioningMessage)"
    message="app $namespace_id state: $namespace_state $namespace_transitioning_message"
    if [ "$message" != "$previous_message" ]; then
        previous_message="$message"
        echo "$message"
    fi
    [ "$namespace_state" = 'active' ] && break
    sleep .5
done

# deploy the nfs-client-provisioner helm chart.
# NB for some reason, the deploy fails a few times before eventually succeeding,
#    so we use --retry-on-http-error.
# TODO is the helm catalog still updating before this happens? something else is not ready?
echo "deploying the nfs-client-provisioner app..."
set -x
app_response="$(wget -O- \
    --retry-on-http-error=500 \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --post-data '{
        "prune": false,
        "type": "app",
        "name": "nfs-client-provisioner",
        "answers": {
            "nfs.server": "'$nfs_server'",
            "nfs.path": "'$nfs_path'"
        },
        "targetNamespace": "nfs-client-provisioner",
        "externalId": "catalog://?catalog=helm&template=nfs-client-provisioner&version='$nfs_client_provisioner_version'",
        "projectId": "'$project_id'",
        "valuesYaml": ""
    }' \
    "$rancher_server_url/v3/projects/$project_id/app")"
app_id="$(echo "$app_response" | jq -r '.id')"
set +x

# wait for app to be active.
echo "waiting for nfs-client-provisioner app to be active..."
previous_message=""
while true; do
    app_response="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $admin_api_token" \
            "$rancher_server_url/v3/project/$project_id/apps/$app_id")"
    app_state="$(echo "$app_response" | jq -r .state)"
    app_transitioning_message="$(echo "$app_response" | jq -r .transitioningMessage)"
    message="app $app_id state: $app_state $app_transitioning_message"
    if [ "$message" != "$previous_message" ]; then
        previous_message="$message"
        echo "$message"
    fi
    [ "$app_state" = 'active' ] && break
    sleep .5
done
