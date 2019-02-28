#!/bin/bash
echo ""

# add bonus scripts
/home/admin/91addBonus.sh

###### SWAP & FS
echo ""
echo "*** SWAP file ***"
swapExists=$(swapon -s | grep -c /mnt/hdd/swapfile)
if [ ${swapExists} -eq 1 ]; then
  echo "SWAP on HDD already exists"
else
  echo "No SWAP found ... creating 1GB SWAP on HDD"
  sudo sed -i "12s/.*/CONF_SWAPFILE=\/mnt\/hdd\/swapfile/" /etc/dphys-swapfile
  sudo sed -i "16s/.*/CONF_SWAPSIZE=1024/" /etc/dphys-swapfile
  echo "OK - edited /etc/dphys-swapfile"
  echo "Creating file ... this can take some seconds .."
  sudo dd if=/dev/zero of=/mnt/hdd/swapfile bs=1024 count=1024000
  sudo mkswap /mnt/hdd/swapfile
  sudo dphys-swapfile setup
  sudo chmod 0600 /mnt/hdd/swapfile
  sudo dphys-swapfile swapon

  # expand FS of SD
  echo "*** Expand RootFS ***"
  sudo raspi-config --expand-rootfs
  echo ""
fi

swapExists=$(swapon -s | grep -c /mnt/hdd/swapfile)
if [ ${swapExists} -eq 1 ]; then
  echo "OK - SWAP is working"
else
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING - Not able to to build SWAP on HDD"
  echo "This is not critical ... but try to fix later."
  echo "--> will continue in 60 seconds <--"
  sleep 60
fi

# firewall - just install (not configure)
echo ""
echo "*** Setting and Activating Firewall ***"
sudo apt-get install -y ufw
echo "deny incoming connection on other ports"
sudo ufw default deny incoming
echo "allow outgoing connections"
sudo ufw default allow outgoing
echo "allow: ssh"
sudo ufw allow ssh
echo "allow: bitcoin testnet"
sudo ufw allow 18333 comment 'bitcoin testnet'
echo "allow: bitcoin mainnet"
sudo ufw allow 8333 comment 'bitcoin mainnet'
echo "allow: litecoin mainnet"
sudo ufw allow 9333 comment 'litecoin mainnet'
echo 'allow: lightning testnet'
sudo ufw allow 19735 comment 'lightning testnet'
echo "allow: lightning mainnet"
sudo ufw allow 9735 comment 'lightning mainnet'
echo "allow: lightning gRPC"
sudo ufw allow 10009 comment 'lightning gRPC'
echo "allow: lightning REST API"
sudo ufw allow 8080 comment 'lightning REST API'
echo "allow: transmission"
sudo ufw allow 51413 comment 'transmission'
echo "allow: local web admin"
sudo ufw allow from 192.168.0.0/16 to any port 80 comment 'allow local LAN web'
echo "open firewall for  auto nat discover (see issue #129)"
sudo ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
echo "enable lazy firewall"
sudo ufw --force enable
echo ""

# update system
echo ""
echo "*** Update System ***"
sudo apt-mark hold raspberrypi-bootloader
sudo apt-get update
echo "OK - System is now up to date"

# mark setup is done
sudo sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info
