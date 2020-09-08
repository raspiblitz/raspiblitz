#!/bin/bash -eux

# Add vagrant user to sudoers.
echo "vagrant        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers

# Disable daily apt unattended updates.
echo 'APT::Periodic::Enable "0";' >> /etc/apt/apt.conf.d/10periodic

apt update
apt upgrade -y

apt install -y dkms make linux-headers-amd64 parted
mkdir -p /mnt/vbox/
mount  /home/vagrant/VBoxGuestAdditions.iso /mnt/vbox
/mnt/vbox/VBoxLinuxAdditions.run --nox11

mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
wget --no-check-certificate \
     https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub \
     -O /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh

