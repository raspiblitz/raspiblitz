#!/bin/bash

echo "************* Vagrant Provisioning ********************"

echo 'Syncing local code with RaspiBlitzVM'

# make sure the lastest sync script is in place
cp /vagrant/home.admin/config.scripts/blitz.github.sh /home/admin/config.scripts/blitz.github.sh

# execute 'patch' command to sync laptop with VM
/home/admin/config.scripts/blitz.github.sh -run

source <(/home/admin/config.scripts/internet.sh status)

echo
echo "************* NEXT ********************"
echo "vagrant ssh --> ssh into your RaspiBlitzVM"
echo "ssh admin@${localip} --> ssh into with password A"
echo "vagrant provision --> trigger code sync from outside VM"
echo "patch --> trigger code sync from inside the VM"
echo 