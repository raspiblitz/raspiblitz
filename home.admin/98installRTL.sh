#!/bin/sh

# INSTALLING THE RTL Webinterface from
# https://github.com/ShahanaFarooqui/RTL/blob/master/README.md

# get the local network IP to be displayed on the lCD
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

echo "*** Check if RTL is installed ***"
isInstalled=$(sudo ls /etc/systemd/system/RTL.service | grep -c 'RTL.service')
if [ ${isInstalled} -eq 1 ]; then
  echo "!! FAIL - RTL Service is already installed."
  echo "Try to open the following URL in your local webrowser"
  echo "and unlock your wallet from there with PASSWORD C."
  echo "---> http://${localip}:3000"
  echo ""
  echo "If its still not running, check service with:"
  echo "sudo systemctl status RTL"
  exit 1
fi

echo "*** Dialog ***"
dialog --title "Install: Ride The Lightning Web Interface"  --yesno "This is still experimental and very reckless:\nOnce your wallet is unlocked EVERYBODY in your\nLOCAL NETWORK can CONTROL YOUR NODE with RTL!\nDo you really want to install RTL?" 6 50
response=$?
case $response in
  1) exit 1 ;;
esac

# disable RPC listen
# to prevent tls cer auth error
echo "*** Modify lnd.conf ***"
sudo sed -i "s/^rpclisten=0.0.0.0:10009/#rpclisten=0.0.0.0:10009/g" /mnt/hdd/lnd/lnd.conf
sudo systemctl restart lnd
echo ""

# install latest nodejs
echo "*** Install NodeJS ***"
curl -sL https://deb.nodesource.com/setup_11.x | sudo -E bash -
sudo apt-get install -y nodejs
echo ""

# close source code
echo "*** Get the RTL Source Code ***"
git clone https://github.com/ShahanaFarooqui/RTL.git
cd RTL
npm install
cd ..
echo ""

# open firewall
echo "*** Updating Firewall ***"
sudo ufw allow 3000
sudo ufw --force enable
echo ""

# install service
echo "*** Install RTL as a Boot Service (systemd) ***"
sudo cp /home/admin/assets/RTL.service /etc/systemd/system/RTL.service
sudo systemctl enable RTL
sudo systemctl start RTL
sleep 2
echo ""

# install service
echo "*** READY ***"
echo "RTL web servcie should be installed and running now."
echo ""
echo "Try to open the following URL in your local webrowser"
echo "and unlock your wallet from there with PASSWORD C."
echo "---> http://${localip}:3000"
echo ""
echo "RTL web server will now start with every new boot."
echo "Always unlock your wallet from there now."
echo "Just use RTL from same local network, DONT forward"
echo "port 3000 on your internet router to the RaspiBlitz."
echo ""
echo "Have fun 'Riding the Lightning' (RTL) :D"