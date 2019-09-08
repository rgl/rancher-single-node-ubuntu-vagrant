#!/bin/bash
set -eux

jenkins_helm_version="${1:-1.6.0}"; shift || true # see https://github.com/helm/charts/blob/master/stable/jenkins/Chart.yaml

cd $(dirname $0)

# deploy the jenkins helm chart.
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
# see https://github.com/helm/charts/tree/master/stable/jenkins
# see https://github.com/helm/charts/commits/master/stable/jenkins
# see https://github.com/helm/charts/tree/b59766d2d37aab540dcb64ee1e0e6c4e0f20f92b/stable/jenkins
echo "deploying the jenkins app..."
rancher app install \
    --version $jenkins_helm_version \
    --values values.yaml \
    --namespace jenkins \
    cattle-global-data:helm-jenkins \
    jenkins

echo "waiting for the jenkins app to be active..."
rancher wait --timeout=600 jenkins

jenkins_password="$(kubectl get secret --namespace jenkins jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)"
echo "jenkins admin password is $jenkins_password"
