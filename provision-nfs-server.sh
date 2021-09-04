#!/bin/bash
set -eux

ip_address="${1:-10.10.0.2}"; shift || true
ip_network="${1:-10.10.0.3/24}"; shift || true

#
# provision the NFS server.
# see exports(5).

apt-get install -y nfs-kernel-server
install -d -o nobody -g nogroup -m 700 /var/nfs
cat >>/etc/exports <<EOF
/var/nfs $ip_network(fsid=0,rw,no_subtree_check)
EOF
systemctl restart nfs-kernel-server

# test access to the NFS server using NFSv3 (UDP and TCP) and NFSv4 (TCP).
showmount -e $ip_address
rpcinfo -u $ip_address nfs 3
rpcinfo -t $ip_address nfs 3
rpcinfo -t $ip_address nfs 4
