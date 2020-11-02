# About

This is a [single node rancher](https://rancher.com/docs/rancher/v2.x/en/installation/single-node/) server.

## Usage

Install the [ubuntu-20.04-amd64](https://github.com/rgl/ubuntu-vagrant) box.

Launch the environment:

```bash
vagrant up --provider=libvirt # or --provider=virtualbox
```

Configure your host DNS resolver to delegate the `rancher.test` domain to the `pandora` machine like described in this document. Or add the environment hosts to your machine `hosts` file:

```plain
10.1.0.2 pandora.rancher.test
10.1.0.3 server.rancher.test
```

Access the rancher server at https://server.rancher.test:8443 and login with the default `admin` username and password.

The docker registry is at https://pandora.rancher.test:5000.

You can access the example cluster from the host with, e.g.:

```bash
export KUBECONFIG=$PWD/shared/admin.conf
kubectl version --short
kubectl cluster-info
kubectl api-versions
kubectl api-resources -o wide
kubectl get namespaces
kubectl get all --all-namespaces -o wide
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp
```

### Hyper-V

Create the required virtual switches:

```bash
PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass <<'EOF'
@(
  @{Name='rancher'; IpAddress='10.1.0.1'}
) | ForEach-Object {
  $switchName = $_.Name
  $switchIpAddress = $_.IpAddress
  $networkAdapterName = "vEthernet ($switchName)"
  $networkAdapterIpAddress = $switchIpAddress
  $networkAdapterIpPrefixLength = 24

  # create the vSwitch.
  New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null

  # assign it an host IP address.
  $networkAdapter = Get-NetAdapter $networkAdapterName
  $networkAdapter | New-NetIPAddress `
      -IPAddress $networkAdapterIpAddress `
      -PrefixLength $networkAdapterIpPrefixLength `
      | Out-Null
}

# remove all virtual switches from the windows firewall.
Set-NetFirewallProfile `
    -DisabledInterfaceAliases (
            Get-NetAdapter -name "vEthernet*" | Where-Object {$_.ifIndex}
        ).InterfaceAlias
EOF
```

## DNS

Make sure that all of the following commands return the IP address of our `pandora` dns server:

```bash
vagrant ssh server
sudo su -l
docker run -i --rm --name test debian:buster-slim cat /etc/resolv.conf # => nameserver 10.1.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    -- \
    cat /etc/resolv.conf # => nameserver 10.1.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    -- \
    cat /etc/nginx/nginx.conf | grep resolver # => resolver 10.1.0.2 valid=30s;
```

## Host DNS resolver

To delegate the `rancher.test` zone to the kubernetes managed external dns server (running in pandora) you need to configure your system to delegate that DNS zone to the pandora DNS server, for that, you can configure your system to only use dnsmasq.

For example, on my Ubuntu 20.04 Desktop, I have uninstalled `resolvconf`, disabled `NetworkManager`, and manually configured the network interfaces:

```bash
sudo su -l
for n in NetworkManager NetworkManager-wait-online NetworkManager-dispatcher network-manager; do
    systemctl mask --now $n
done
apt-get remove --purge resolvconf
cat >/etc/network/interfaces <<'EOF'
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

auto enp3s0
iface enp3s0 inet dhcp
EOF
reboot
```

Then, replaced `systemd-resolved` with `dnsmasq`:

```bash
sudo su -l
apt-get install -y --no-install-recommends dnsutils dnsmasq
systemctl mask --now systemd-resolved
cat >/etc/dnsmasq.d/local.conf <<EOF
no-resolv
bind-interfaces
interface=lo
listen-address=127.0.0.1
# delegate the rancher.test zone to the pandora DNS server IP address.
server=/rancher.test/10.1.0.2
# delegate to the Cloudflare/APNIC Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
server=1.1.1.1
server=1.0.0.1
# delegate to the Google Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
#server=8.8.8.8
#server=8.8.4.4
EOF
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF
systemctl restart dnsmasq
exit
```

Then start all the machines and test the DNS resolution:

```bash
vagrant up
dig pandora.rancher.test
dig kubernetes-hello.rancher.test
```

## References

* https://rancher.com/docs/rancher/v2.x/en/troubleshooting/kubernetes-components/
* https://github.com/rancher/quickstart
* https://github.com/rancher/api-spec
* https://kubernetes.io/docs/reference/kubectl/cheatsheet/
* https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
