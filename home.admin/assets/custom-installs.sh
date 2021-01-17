#!/bin/bash

# This script runs with sudo rights after an update/recovery from a fresh sd card.
# This is the place to put all the install commands, cronjobs or editing of system configs 
# for your personal modifications of RaspiBlitz

# note: use absolute paths if you point to specific files

#echo "There are no custom user installs so far."


sudo apt-get --yes --force-yes install mc


#sudo systemctl disable dphys-swapfile
#remove this dinosaur age shit
#tips if not working:
# rm all dphys-swapfile
# sudo find / -name swapfile
# sudo rm -f "swapfile"


sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOT

#On firsrt boot of new installation, device gets ip 192.168.0.100, I want always the same ip, so set satic ip here and changed the file:
# /usr/local/gocode/src/github.com/btcsuite/btcd/addrmgr/addrmanager_test.go do work.
# to see if on first boot they are applied, so it will never get .100, and always the ip that I want.
# source: https://hexang.org/yh/burrow/blob/f9b2b4a10022520712d3711845a26397d3b49fa9/vendor/github.com/btcsuite/btcd/addrmgr/addrmanager_test.go

# Custom static IP address for eth0.
interface eth0
static ip_address=192.168.0.210/24
static routers=192.168.0.1
static domain_name_servers=192.168.0.1

# Custom static IP address for wlan0.
interface wlan0
static ip_address=192.168.0.210/24
static routers=192.168.0.1
static domain_name_servers=192.168.0.1
EOT
