#!/bin/bash

# load network
network=`cat .network`

# location of TOR config
torrc="/etc/tor/torrc"

echo "*** Stopping all Services ***"
sudo systemctl stop lnd
sudo systemctl stop ${network}d
sudo systemctl stop tor@default
echo ""

echo "*** Disable TOR service ***"
sudo systemctl disable tor@default
echo ""

echo "*** Changing ${network} Config ***"
sudo cat /home/bitcoin/.${network}/${network}.conf | grep -Ev 'onlynet=onion|.onion' | sudo tee /home/bitcoin/.${network}/${network}.conf
sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
sudo chown admin:admin /home/admin/.${network}/${network}.conf

echo "*** Removing TOR from LND ***"
sudo systemctl disable lnd
sed -i "5s/.*/Wants=${network}d.service/" ./assets/lnd.service
sed -i "6s/.*/After=${network}d.service/" ./assets/lnd.service
sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service
sudo chmod +x /etc/systemd/system/lnd.service
sudo systemctl enable lnd
echo "OK"
echo ""

echo "*** Remove Tor ***"
sudo apt remove tor tor-arm -y
echo ""

echo "*** Remove dirmngr ***"
sudo apt remove dirmngr
echo ""

echo "*** Remove NYX ***"
sudo pip uninstall nyx -y
echo ""

echo "*** Remove TOR Files/Config ***"
sudo rm -r -f /mnt/hdd/tor
echo ""

echo "*** Finshing Setup / REBOOT ***"
echo "OK - all should be set"
echo ""
echo "PRESS ENTER ... to REBOOT"
read key

sudo shutdown -r now
exit 0