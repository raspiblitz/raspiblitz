#!/usr/bin/env bash


## Description: This script configure bitcoin and lightning implementations to be used with tor
## Background:
## https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
## https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
## https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

torrc="/etc/tor/torrc"

# command info
usage(){
 echo "script to switch Tor on or off"
 echo "tor.network.sh [status|on|off|btcconf-on|btcconf-off|update]"
 exit 1
}

# add default value to raspi config if needed
sudo grep -q "runBehindTor" /mnt/hdd/raspiblitz.conf || { echo "runBehindTor=off" | sudo tee -a /mnt/hdd/raspiblitz.conf; }

if [ "$1" != "update" ]; then
  # stop services (if running)
  echo "making sure services are not running"
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl stop ${network}d 2>/dev/null
  sudo systemctl stop tor@default 2>/dev/null
fi

activateBitcoinOverTor()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/."${network}"/"${network}".conf | grep -c "${network}.conf")
  if [ "${btcExists}" -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTor

    sudo chmod 777 "/home/bitcoin/.${network}/${network}.conf"
    echo "Adding Tor config to the the ${network}.conf ..."
    sudo sed -i "s/^torpassword=.*//g" "/home/bitcoin/.${network}/${network}.conf"
    echo "onlynet=onion" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"
    echo "proxy=127.0.0.1:9050" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"
    echo "main.bind=127.0.0.1" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"
    echo "test.bind=127.0.0.1" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"
    echo "dnsseed=0" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"
    echo "dns=0" | sudo tee -a "/home/bitcoin/.${network}/${network}.conf"

    # remove empty lines
    sudo sed -i '/^ *$/d' "/home/bitcoin/.${network}/${network}.conf"
    sudo chmod 644 "/home/bitcoin/.${network}/${network}.conf"

    # copy new bitcoin.conf to admin user for cli access
    sudo cp "/home/bitcoin/.${network}/${network}.conf" "/home/admin/.${network}/${network}.conf"
    sudo chown admin:admin "/home/admin/.${network}/${network}.conf"

  else
    echo "BTC config does not found (yet) -  try with 'tor.network.sh btcconf-on' again later"
  fi
}

deactivateBitcoinOverTor()
{
  # always make sure also to remove old settings
  sudo sed -i "s/^onlynet=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^main.addnode=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^test.addnode=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^proxy=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^main.bind=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^test.bind=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^dnsseed=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  sudo sed -i "s/^dns=.*//g" "/home/bitcoin/.${network}/${network}.conf"
  # remove empty lines
  sudo sed -i '/^ *$/d' "/home/bitcoin/.${network}/${network}.conf"
  sudo cp "/home/bitcoin/.${network}/${network}.conf" "/home/admin/.${network}/${network}.conf"
  sudo chown admin:admin "/home/admin/.${network}/${network}.conf"
}

# check and load raspiblitz config
# to know which network is running
[ -f "/home/admin/raspiblitz.info" ] && . /home/admin/raspiblitz.info
[ -f "/mnt/hdd/raspiblitz.conf" ] && . /mnt/hdd/raspiblitz.conf

torActive=$(sudo systemctl is-active tor@default | grep -c "active")
curl --socks5 127.0.0.1:9050 --socks5-hostname 127.0.0.1:9050 -m 5 -s https://check.torproject.org/api/ip | grep -q "\"IsTor\":true" && torFunctional=1

case "$1" in

  status)
    echo "torEnabled=${runBehindTor}"
    echo "torActive=${torActive}"
    echo "torFunctional=${torFunctional}"
    echo "config=${torrc}"
  ;;


  btcconf-on) activateBitcoinOverTor; exit 0;;


  btcconf-off) deactivateBitcoinOverTor; exit 0;;


  1|on)
    echo "# switching Tor ON"

    # make sure the network was set (by sourcing raspiblitz.conf)
    if [ ${#network} -eq 0 ]; then
      echo "!! FAIL - unknown network due to missing /mnt/hdd/raspiblitz.conf"
      echo "# switching Tor config on for RaspiBlitz services is just possible after basic hdd/ssd setup"
      echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
      exit 1
    fi

    /home/admin/config.scripts/tor.install.sh

    # setting value in raspi blitz config
    sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /mnt/hdd/raspiblitz.conf

    # ACTIVATE BITCOIN OVER TOR (function call)
    activateBitcoinOverTor

    # ACTIVATE APPS OVER TOR
    . /mnt/hdd/raspiblitz.conf 2>/dev/null
    [ "${BTCRPCexplorer}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh btc-rpc-explorer 80 3022 443 3023
    [ "${rtlWebinterface}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh RTL 80 3002 443 3003
    [ "${BTCPayServer}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh btcpay 80 23002 443 23003
    [ "${ElectRS}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh electrs 50002 50002 50001 50001
    [ "${LNBits}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
    [ "${thunderhub}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh thunderhub 80 3012 443 3013
    [ "${specter}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh specter 443 25441
    if [ "${sphinxrelay}" = "on" ]; then
      /home/admin/config.scripts/tor.onion-service.sh sphinxrelay 80 3302 443 3303
      toraddress=$(sudo cat /mnt/hdd/tor/sphinxrelay/hostname 2>/dev/null)
      sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
    fi

    echo "Setup logrotate"
    # add logrotate config for modified Tor dir on ext. disk
    sudo tee /etc/logrotate.d/raspiblitz-tor >/dev/null <<EOF
/mnt/hdd/tor/*log {
        daily
        rotate 5
        compress
        delaycompress
        missingok
        notifempty
        create 0640 debian-tor debian-tor
        sharedscripts
        postrotate
                if invoke-rc.d tor status > /dev/null; then
                        invoke-rc.d tor reload > /dev/null
                fi
        endscript
}
EOF

    # make sure its the correct owner before last Tor restart
    sudo chmod -R 700 /mnt/hdd/tor
    sudo chown -R debian-tor:debian-tor /mnt/hdd/tor
    sudo systemctl restart tor@default
    echo "OK - Tor is now $(sudo systemctl is-active tor@default)"
    echo "needs reboot to activate new setting"
  ;;


  0|off)
    echo "# switching Tor OFF"

    # setting value in raspi blitz config
    sudo sed -i "s/^runBehindTor=.*/runBehindTor=off/g" /mnt/hdd/raspiblitz.conf

    # disable tor service
    echo "# *** Disable Tor service ***"
    sudo systemctl disable tor@default
    echo

    # deactivate bitcoin over tor (function call)
    deactivateBitcoinOverTor
    echo

    sudo /home/admin/config.scripts/internet.sh update-publicip

    if [ "${lightning}" = "lnd" ] || [ "${lnd}" = "on" ] || [ "${lnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Mainnet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/lnd/lnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/lnd/lnd.conf
      sudo systemctl restart lnd
    fi

    if [ "${tlnd}" = "on" ] || [ "${tlnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Testnet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/lnd/tlnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/lnd/tlnd.conf
      sudo systemctl restart tlnd
    fi

    if [ "${slnd}" = "on" ] || [ "${slnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Signet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/lnd/slnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/lnd/slnd.conf
      sudo systemctl restart slnd
    fi

    echo "# OK"
    echo
    echo "# *** Stop Tor service ***"
    sudo systemctl stop tor@default
    echo

    if [ "$2" = "clear" ]; then
        echo "# *** Uninstall Tor & Delete Data ***"
        sudo rm -r /mnt/hdd/tor 2>/dev/null
        sudo apt remove -y tor nyx
    fi

    echo "# needs reboot to activate new setting"
  ;;


  update)
    /home/admin/config.scripts/tor.update.sh
    if [ "$(sudo systemctl is-active lnd | grep -c "active")" -gt 0 ];then
      echo "# LND needs to be restarted"
      sudo systemctl restart lnd
      sudo systemctl restart tlnd 2>/dev/null
      sudo systemctl restart slnd 2>/dev/null
      sleep 10
      lncli unlock
    fi
  ;;

  *) usage

esac
