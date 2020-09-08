# -*- mode: ruby -*-
# vi: set ft=ruby :

# in order to attach a secondary disk we need to enable vagrant disk experimental feature
if ENV['VAGRANT_EXPERIMENTAL'] != 'disks'
  ENV['VAGRANT_EXPERIMENTAL'] = 'disks'
end

Vagrant.configure('2') do |config|
  config.vm.box = 'raspiblitz'

  config.ssh.username = 'admin'
  config.ssh.password = 'raspiblitz'
  config.ssh.insert_key = true

  config.vm.disk :disk, size: '16GB', primary: true
  config.vm.disk :disk, size: '500GB', name: 'external_disk'

  config.vm.provider 'virtualbox' do |vb, override|
    vb.memory = 2048
    vb.customize ['modifyvm', :id, '--usbxhci', 'on']
  end

  config.vm.provision 'shell',
                      privileged: false,
                      run: 'always',
                      path: 'alternative.platforms/amd64/packer/scripts/init_vagrant.sh'
end
