# About

This is a [single node rancher](https://rancher.com/docs/rancher/v2.x/en/installation/single-node/) server.

## Usage

Install the [ubuntu-18.04-amd64](https://github.com/rgl/ubuntu-vagrant) box.

Launch the environment:

```bash
vagrant up --provider=libvirt # or --provider=virtualbox
```

Add the environment hosts to your machine `hosts` file:

```plain
10.1.0.2 pandora.rancher.test
10.1.0.3 server.rancher.test
```

Access the rancher server at https://server.rancher.test:8443 and login with the default `admin` username and password.

The docker registry is at https://pandora.rancher.test:5000.

## DNS

Make sure that all of the following commands return the IP address of our `pandora` dns server:

```bash
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf # => nameserver 10.1.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    cat /etc/resolv.conf # => nameserver 10.1.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    cat /etc/nginx/nginx.conf | grep resolver # => resolver 10.1.0.2 valid=30s;
```

## References

* https://rancher.com/docs/rancher/v2.x/en/troubleshooting/kubernetes-components/
* https://github.com/rancher/quickstart
* https://github.com/rancher/api-spec
* https://kubernetes.io/docs/reference/kubectl/cheatsheet/
