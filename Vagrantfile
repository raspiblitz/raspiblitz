# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure('2') do |config|

  config.vm.box = 'raspiblitz'

  config.vm.network "private_network", type: "dhcp"

  config.ssh.username = 'admin'
  config.ssh.password = 'raspiblitz'
  config.ssh.insert_key = true

  config.vm.disk :disk, size: '16GB', primary: true

  config.vm.provider 'virtualbox' do |vb, override|
    vb.memory = 2048
  end

  config.vm.provision 'shell',
                      privileged: false,
                      run: 'always',
                      path: 'alternative.platforms/amd64/packer/scripts/init_vagrant.sh'
end
