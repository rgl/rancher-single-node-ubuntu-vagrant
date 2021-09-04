# to make sure the nodes are created in order we have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

# to be able to configure hyper-v.
ENV['VAGRANT_EXPERIMENTAL'] = 'typed_triggers'

config_pandora_fqdn = 'pandora.rancher.test'
config_pandora_ip_address = '10.10.0.2'
config_server_fqdn = 'server.rancher.test'
config_server_ip_address = '10.10.0.3'
config_admin_password = 'admin'
config_docker_version = '20.10.8' # NB execute apt-cache madison docker-ce to known the available versions.
config_rancher_version = 'v2.6.0' # see https://github.com/rancher/rancher/releases
config_rancher_cli_version = 'v2.4.12' # see https://github.com/rancher/cli/releases
# set the example cluster kubernetes version.
# NB the rancher (local) cluster kubernetes version cannot be set as its
#    bundled with the rancher version defined with config_rancher_version.
# see https://releases.rancher.com/kontainer-driver-metadata/release-v2.6/data.json
#     NB this data.json file is defined by the rke-metadata-config setting in
#        the rancher global settings page at:
#        https://server.rancher.test:8443/dashboard/c/local/settings/management.cattle.io.setting
# see https://raw.githubusercontent.com/rancher/kontainer-driver-metadata/release-v2.6/data/data.json
#     jq '.K8sVersionRKESystemImages | keys' data.json # for rke1. e.g. v1.21.4-rancher1-1
#     jq '.rke2.releases[].version' data.json          # for rke2. e.g. v1.21.4+rke2r2
#     jq '.k3s.releases[].version' data.json           # for k3s.  e.g. v1.21.4+k3s1
#     NB because provision-rancher.sh is deploying a RKE1 example cluster, you
#        MUST use a version of it here too.
config_k8s_version = 'v1.21.4-rancher1-1'
config_kubectl_version = config_k8s_version.gsub(/v([\.\d]+).+/, '\1')
config_krew_version = 'v0.4.1' # NB see https://github.com/kubernetes-sigs/krew
config_metallb_helm_chart_version = '2.5.4' # see https://github.com/bitnami/charts/blob/master/bitnami/metallb/Chart.yaml
config_metallb_ip_addresses = '10.10.0.10-10.10.0.20' # MetalLB will allocate IP addresses from this range.
config_nfs_client_provisioner_version = '4.0.13' # see https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/releases

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
  config.vm.box = 'ubuntu-20.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.memory = 5*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = false
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 5*1024
    vb.cpus = 4
  end

  config.vm.provider 'hyperv' do |hv, config|
    hv.linked_clone = true
    hv.memory = 5*1024
    hv.cpus = 4
    hv.enable_virtualization_extensions = false # nested virtualization.
    hv.vlan_id = ENV['HYPERV_VLAN_ID']
    # set the management network adapter.
    # see https://github.com/hashicorp/vagrant/issues/7915
    # see https://github.com/hashicorp/vagrant/blob/10faa599e7c10541f8b7acf2f8a23727d4d44b6e/plugins/providers/hyperv/action/configure.rb#L21-L35
    config.vm.network :private_network,
      bridge: ENV['HYPERV_SWITCH_NAME'] if ENV['HYPERV_SWITCH_NAME']
    config.vm.synced_folder '.', '/vagrant',
      type: 'smb',
      smb_username: ENV['VAGRANT_SMB_USERNAME'] || ENV['USER'],
      smb_password: ENV['VAGRANT_SMB_PASSWORD']
    # further configure the VM (e.g. manage the network adapters).
    config.trigger.before :'VagrantPlugins::HyperV::Action::StartInstance', type: :action do |trigger|
      trigger.ruby do |env, machine|
        # see https://github.com/hashicorp/vagrant/blob/v2.2.10/lib/vagrant/machine.rb#L13
        # see https://github.com/hashicorp/vagrant/blob/v2.2.10/plugins/kernel_v2/config/vm.rb#L716
        bridges = machine.config.vm.networks.select{|type, options| type == :private_network && options.key?(:hyperv__bridge)}.map do |type, options|
          mac_address_spoofing = false
          mac_address_spoofing = options[:hyperv__mac_address_spoofing] if options.key?(:hyperv__mac_address_spoofing)
          [options[:hyperv__bridge], mac_address_spoofing]
        end
        system(
          'PowerShell',
          '-NoLogo',
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'configure-hyperv.ps1',
          machine.id,
          bridges.to_json
        )
      end
    end
  end

  config.vm.define :pandora do |config|
    config.vm.provider 'libvirt' do |lv, config|
      lv.memory = 1*1024
    end
    config.vm.provider 'virtualbox' do |vb|
      vb.memory = 1*1024
    end
    config.vm.provider 'hyperv' do |hv|
      hv.memory = 1*1024
    end
    config.vm.hostname = config_pandora_fqdn
    config.vm.network :private_network,
      ip: config_pandora_ip_address,
      libvirt__forward_mode: 'route',
      libvirt__dhcp_enabled: false,
      hyperv__bridge: 'rancher'
    config.vm.provision :shell,
      path: 'configure-hyperv.sh',
      args: [
        config_pandora_ip_address
      ],
      run: 'always'
    config.vm.provision 'shell', inline: 'echo "$1" >/etc/hosts', args: [hosts]
    config.vm.provision 'shell', path: 'provision-base.sh'
    config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-dns-server.sh', args: [config_pandora_ip_address, config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-nfs-server.sh', args: [config_pandora_ip_address, "#{config_server_ip_address}/24"]
    config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version]
    config.vm.provision 'shell', path: 'provision-registry.sh', args: [config_pandora_fqdn]
  end

  config.vm.define :server do |config|
    config.vm.hostname = config_server_fqdn
    config.vm.network :private_network,
      ip: config_server_ip_address,
      libvirt__forward_mode: 'route',
      libvirt__dhcp_enabled: false,
      hyperv__bridge: 'rancher'
    config.vm.provision :shell,
      path: 'configure-hyperv.sh',
      args: [
        config_server_ip_address
      ],
      run: 'always'
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
      config_rancher_cli_version,
      config_k8s_version,
      config_kubectl_version,
      config_krew_version,
    ]
    config.vm.provision 'shell', path: 'provision-metallb.sh', args: [config_metallb_helm_chart_version, config_metallb_ip_addresses]
    config.vm.provision 'shell', path: 'provision-external-dns-pdns.sh', args: [config_pandora_fqdn, config_server_fqdn]
    config.vm.provision 'shell', path: 'provision-rancher-nfs-client.sh', args: [
      config_pandora_fqdn,
      config_nfs_client_provisioner_version,
    ]
    config.vm.provision 'shell', inline: 'bash /vagrant/examples/kubernetes-hello/build.sh "$*"', args: [config_pandora_fqdn]
    config.vm.provision 'shell', inline: 'bash /vagrant/examples/kubernetes-hello/deploy.sh'
    config.vm.provision 'shell', path: 'summary.sh', args: [
      config_pandora_fqdn,
    ]
  end
end
