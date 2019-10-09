#!/bin/bash
set -eux

# NB execute apt-cache madison docker-ce to known the available versions.
docker_version="${1:-5:19.03.3~3-0~ubuntu-bionic}"; shift || true

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install docker.
# see https://docs.docker.com/install/linux/docker-ce/ubuntu/
apt-get install -y apt-transport-https software-properties-common gnupg2
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y "docker-ce=$docker_version" "docker-ce-cli=$docker_version" containerd.io

# let the vagrant user manage docker.
usermod -aG docker vagrant
