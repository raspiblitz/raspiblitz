#!/bin/bash

# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md
# https://github.com/bitcoin/bitcoin/blob/master/doc/tor.md

# INFO
# --------------------
# basic install of Tor is done by the build script now .. on/off will just switch service on/off
# also thats where the sources are set and the preparation is done

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to switch Tor on or off"
 echo "tor.network-remove.sh [off|btcconf-off]"
 exit 1
fi

# include lib
. /home/admin/config.scripts/tor.functions.lib

deactivateBitcoinOverTOR()
{
  # always make sure also to remove old settings
  sudo sed -i "s/^onlynet=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^proxy=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dnsseed=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dns=.*//g" /home/bitcoin/.${network}/${network}.conf
  # remove empty lines
  sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
  sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
  sudo chown admin:admin /home/admin/.${network}/${network}.conf
}

# check and load raspiblitz config
# to know which network is running
if [ -f "/home/admin/raspiblitz.info" ]; then
  source /home/admin/raspiblitz.info
fi

if [ -f "/mnt/hdd/raspiblitz.conf" ]; then
  source /mnt/hdd/raspiblitz.conf
fi

# if started with btcconf-off
if [ "$1" = "btcconf-off" ]; then
  deactivateBitcoinOverTOR
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# switching Tor OFF"

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=off/g" /mnt/hdd/raspiblitz.conf

  # *** CURL TOR PROXY ***
  # sudo rm /root/.curlrc
  # sudo rm /home/pi/.curlrc
  # sudo rm /home/admin/.curlrc

  # disable Tor service
  echo "# *** Disable Tor service ***"
  sudo systemctl disable tor@default
  echo ""

  # DEACTIVATE BITCOIN OVER Tor (function call)
  deactivateBitcoinOverTOR
  echo ""

  echo "# *** Removing Tor from LND ***"
  sudo systemctl disable lnd
  echo "# editing /etc/systemd/system/lnd.service"
  sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*/ExecStart=\/usr\/local\/bin\/lnd --externalip=\${publicIP}:\${lndPort} \${lndExtraParameter}/g" /etc/systemd/system/lnd.service

  sudo /home/admin/config.scripts/internet.sh update-publicip

  sudo systemctl enable lnd
  echo "# OK"
  echo ""

  echo "# *** Stop Tor service ***"
  sudo systemctl stop tor@default
  echo ""

  if [ "$2" == "clear" ]; then
      echo "# *** Deinstall Tor & Delete Data ***"
      sudo rm -r /mnt/hdd/tor 2>/dev/null
      sudo apt remove tor nyx -y
  fi

  echo "# needs reboot to activate new setting"
  exit 0
fi
