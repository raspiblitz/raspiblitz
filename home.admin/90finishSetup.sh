#!/bin/bash
echo ""

# TODO: COPY OVER COMPLETLY INTO _provison_.sh

# add bonus scripts (auto install deactivated to reduce third party repos)
/home/admin/91addBonus.sh

###### SWAP File
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${isSwapExternal} -eq 0 ]; then

  echo "No external SWAP found - creating ... "
  sudo /home/admin/config.scripts/blitz.datadrive.sh swap on

else
  echo "SWAP already OK"
fi

####### FIREWALL - just install (not configure)
echo ""
echo "*** Setting and Activating Firewall ***"
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
sudo ufw allow 49200:49250/tcp comment 'rtorrent'
echo "allow: public web HTTP"
sudo ufw allow from any to any port 80 comment 'allow public web HTTP'
echo "allow: local web admin HTTPS"
sudo ufw allow from 10.0.0.0/8 to any port 443 comment 'allow local LAN HTTPS'
sudo ufw allow from 172.16.0.0/12 to any port 443 comment 'allow local LAN HTTPS'
sudo ufw allow from 192.168.0.0/16 to any port 443 comment 'allow local LAN HTTPS'
echo "open firewall for auto nat discover (see issue #129)"
sudo ufw allow proto udp from 10.0.0.0/8 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
sudo ufw allow proto udp from 172.16.0.0/12 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
sudo ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
echo "enable lazy firewall"
sudo ufw --force enable
echo ""

# update system
echo ""
echo "*** Update System ***"
sudo apt-mark hold raspberrypi-bootloader
sudo apt-get update -y
echo "OK - System is now up to date"

# mark setup is done
sudo sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info
