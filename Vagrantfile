# to make sure the nodes are created in order we have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

config_pandora_fqdn = 'pandora.rancher.test'
config_pandora_ip_address = '10.1.0.2'
config_server_fqdn = 'server.rancher.test'
config_server_ip_address = '10.1.0.3'
config_admin_password = 'admin'
config_docker_version = '5:19.03.1~3-0~ubuntu-bionic' # NB execute apt-cache madison docker-ce to known the available versions.
config_rancher_version = 'v2.2.8'
config_k8s_version = 'v1.14.6-rancher1-1'
config_kubectl_version = '1.14.6-00' # NB execute apt-cache madison kubectl to known the available versions.

hosts = """
127.0.0.1	localhost
#{config_pandora_ip_address} #{config_pandora_fqdn}
#{config_server_ip_address} #{config_server_fqdn}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
"""

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-18.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.memory = 4*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 4*1024
    vb.cpus = 4
  end

  config.vm.define :pandora do |config|
    config.vm.provider 'libvirt' do |lv, config|
      lv.memory = 2*1024
    end
    config.vm.provider 'virtualbox' do |vb|
      vb.memory = 2*1024
    end
    config.vm.hostname = config_pandora_fqdn
    config.vm.network :private_network, ip: config_pandora_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.provision 'shell', inline: 'echo "$1" >/etc/hosts', args: [hosts]
    config.vm.provision 'shell', path: 'provision-base.sh'
    config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-dns-server.sh', args: [config_pandora_ip_address, config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version]
    config.vm.provision 'shell', path: 'provision-registry.sh', args: [config_pandora_fqdn]
  end

  config.vm.define :server do |config|
    config.vm.hostname = config_server_fqdn
    config.vm.network :private_network, ip: config_server_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.provision 'shell', path: 'provision-base.sh'
    config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_server_fqdn]
    config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [config_pandora_ip_address]
    config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version]
    config.vm.provision 'shell', path: 'provision-rancher.sh', args: [
      config_pandora_fqdn,
      config_server_fqdn,
      config_server_ip_address,
      config_admin_password,
      config_rancher_version,
      config_k8s_version,
      config_kubectl_version,
    ]
    config.vm.provision 'shell', inline: '/vagrant/examples/go-info/build.sh "$*"', args: [config_pandora_fqdn]
    config.vm.provision 'shell', inline: '/vagrant/examples/go-info/deploy.sh'
    config.vm.provision 'shell', path: 'summary.sh', args: [
      config_pandora_fqdn,
    ]
  end
end
