#!/bin/bash

# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

# load network
network=`cat .network`
chain="$(${network}-cli getblockchaininfo | jq -r '.chain')"

# location of TOR config
torrc="/etc/tor/torrc"

# check if TOR was already installed and is funtional
clear
echo ""
echo "*** Check if TOR service is functional ***"
torRunning=$(curl --connect-timeout 10 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org | grep "Congratulations. This browser is configured to use Tor." -c)
if [ ${torRunning} -gt 0 ]; then
  clear
  echo "You are all good - TOR is already running."
  echo ""
  exit 0
else
  echo "TOR not running ... proceed with switching to TOR."
  echo ""
fi

# ask user if to proceed
dialog --title " WARNING " --yesno "At the moment you just can switch TOR on - YOU CANNOT SWITCH BACK. Do you want to proceed?" 8 57
response=$?
case $response in
  1) exit 1;
esac

echo "*** Adding Tor Sources to sources.list ***"
echo "deb http://deb.torproject.org/torproject.org stretch main" | sudo tee -a /etc/apt/sources.list
echo "deb-src http://deb.torproject.org/torproject.org stretch main" | sudo tee -a /etc/apt/sources.list
echo "OK"
echo ""

echo "*** Installing dirmngr ***"
sudo apt install dirmngr
echo ""

## lopp: gpg --keyserver keys.gnupg.net --recv 886DDD89
echo "*** Fetching GPG key ***"
gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
echo ""

echo "*** Updating System ***"
sudo apt-get update
echo ""

echo "*** Install Tor ***"
sudo apt install tor tor-arm -y

echo ""
echo "*** Tor Config ***"
sudo rm -r -f /mnt/hdd/tor 2>/dev/null
sudo mkdir /mnt/hdd/tor
sudo mkdir /mnt/hdd/tor/sys
sudo mkdir /mnt/hdd/tor/web80
sudo mkdir /mnt/hdd/tor/lnd9735
sudo mkdir /mnt/hdd/tor/lndrpc9735
sudo chmod -R 700 /mnt/hdd/tor
sudo chown -R bitcoin:bitcoin /mnt/hdd/tor
cat > ./torrc <<EOF
### See 'man tor', or https://www.torproject.org/docs/tor-manual.html

DataDirectory /mnt/hdd/tor/sys
PidFile /mnt/hdd/tor/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file /mnt/hdd/tor/notice.log
Log info file /mnt/hdd/tor/info.log

RunAsDaemon 1
User bitcoin
PortForwarding 1
ControlPort 9051
SocksPort 9050

CookieAuthFile /mnt/hdd/tor/sys/control_auth_cookie
CookieAuthentication 1
CookieAuthFileGroupReadable 1

# Hidden Service v2 for WEB ADMIN INTERFACE
HiddenServiceDir /mnt/hdd/tor/web80/
HiddenServicePort 80 127.0.0.1:80

# Hidden Service v2 for LND RPC
HiddenServiceDir /mnt/hdd/tor/lndrpc10009/
HiddenServicePort 80 127.0.0.1:10009

# Hidden Service v3 for LND incomming connections (just in case)
# https://trac.torproject.org/projects/tor/wiki/doc/NextGenOnions#Howtosetupyourownprop224service
HiddenServiceDir /mnt/hdd/tor/lnd9735
HiddenServiceVersion 3
HiddenServicePort 9735 127.0.0.1:9735

# NOTE: bitcoind get tor service automatically - see /mnt/hdd/bitcoin for onion key
EOF
sudo rm $torrc
sudo mv ./torrc $torrc
sudo chmod 644 $torrc
sudo chown -R bitcoin:bitcoin /var/run/tor/
echo ""

# NYX - Tor monitor tool
# https://nyx.torproject.org/#home
echo "*** Installing NYX - TOR monitoring Tool ***"
nyxInstalled=$(sudo pip list 2>/dev/null | grep 'nyx' -c)
if [ ${nyxInstalled} -eq 0 ]; then
  sudo pip install nyx
else
  echo "NYX already installed"
fi
echo ""
  
echo "*** Activating TOR system service ***"
echo "ReadWriteDirectories=-/mnt/hdd/tor" | sudo tee -a /lib/systemd/system/tor@default.service
sudo systemctl daemon-reload
sudo systemctl restart tor@default
echo ""

echo "*** Waiting for TOR to boostrap ***"
torIsBootstrapped=0
while [ ${torIsBootstrapped} -eq 0 ]
do
  echo "--- Checking 1 ---"
  date +%s
  sudo cat /mnt/hdd/tor/notice.log 2>/dev/null | grep "Bootstrapped" | tail -n 10
  torIsBootstrapped=$(sudo cat /mnt/hdd/tor/notice.log 2>/dev/null | grep "Bootstrapped 100" -c)
  echo "torIsBootstrapped(${torIsBootstrapped})"
  echo "If this takes too long --> CTRL+c, reboot and check manually"
  sleep 5
done
echo "OK - Tor Bootstrap is ready"
echo ""

echo "*** Changing ${network} Config ***"
networkIsTor=$(sudo cat /home/bitcoin/.${network}/${network}.conf | grep 'onlynet=onion' -c)
if [ ${networkIsTor} -eq 0 ]; then

  echo "Only Connect thru TOR"
  echo "onlynet=onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf

  if [ "${network}" = "bitcoin" ]; then
    echo "Adding some bitcoin onion nodes to connect to"
    echo "addnode=fno4aakpl6sg6y47.onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf
    echo "addnode=toguvy5upyuctudx.onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf
    echo "addnode=ndndword5lpb7eex.onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf
    echo "addnode=6m2iqgnqjxh7ulyk.onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf
    echo "addnode=5tuxetn7tar3q5kp.onion" | sudo tee --append /home/bitcoin/.${network}/${network}.conf
  fi

  sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
  sudo chown admin:admin /home/admin/.${network}/${network}.conf

else
  echo "Chain network already configured for TOR"
fi

echo "*** ${network} re-init - Waiting for Onion Address ***"
# restarting bitcoind to start with tor and generare onion.address
echo "restarting ${network}d ..."
sudo systemctl restart ${network}d
sleep 8
onionAddress=""
while [ ${#onionAddress} -eq 0 ]
do
  echo "--- Checking 2 ---"
  date +%s
  testNetAdd=""
  if [ "${chain}" = "test" ];then
    testNetAdd="/testnet3"
  fi
  sudo cat /mnt/hdd/${network}${testNetAdd}/debug.log 2>/dev/null | grep "tor" | tail -n 10
  onionAddress=$(sudo -u bitcoin ${network}-cli getnetworkinfo | grep '"address"' | cut -d '"' -f4)
  echo "Can take up to 20min - if this takes longer --> CTRL+c, reboot and check manually"
  sleep 5
done
onionPort=$(sudo -u bitcoin ${network}-cli getnetworkinfo | grep '"port"' | tr -dc '0-9')
echo "Your Chain Network Onion Address is: ${onionAddress}:${onionPort}"
echo ""

echo "*** Setting your Onion Address ***"
onionLND=$(sudo cat /mnt/hdd/tor/lnd9735/hostname)
echo "Your Lightning Tor Onion Address is: ${onionLND}:9735"
echo ""

# ACTIVATE LND OVER TOR
echo "*** Putting LND behind TOR ***"
echo "Disable LND again"
sudo systemctl disable lnd
echo "Writing Public Onion Address to /mnt/hdd/tor/v3Address (just in case for TotHiddenServiceV3)"
echo "V3ADDRESS=${onionLND}" | sudo tee /mnt/hdd/tor/v3Address
echo "Configure and Changing to lnd.tor.service"
sed -i "5s/.*/Wants=${network}d.service/" ./assets/lnd.tor.service
sed -i "6s/.*/After=${network}d.service/" ./assets/lnd.tor.service
sudo cp /home/admin/assets/lnd.tor.service /etc/systemd/system/lnd.service
sudo chmod +x /etc/systemd/system/lnd.service
echo "Enable LND again"
sudo systemctl enable lnd
echo "OK"
echo ""

echo "*** Finshing Setup / REBOOT ***"
echo "OK - all should be set"
echo ""
echo "PRESS ENTER ... to REBOOT"
read key

sudo shutdown -r now
exit 0