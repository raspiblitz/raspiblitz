#!/bin/bash

# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

# INFO
# --------------------
# basic install of Tor is done by the build script now .. on/off will just switch service on/off
# also thats where the sources are set and the preparation is done

torrc="/etc/tor/torrc"

## https://github.com/keroserene/snowflake/commits/master
snowflake_commit_hash="af6e2c30e1a6aacc6e7adf9a31df0a387891cc37"


# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = *help* ]; then
 echo "script to switch Tor on or off"
 echo "tor.network.sh [status|on|off|btcconf-on|btcconf-off|update]"
 exit 1
fi

activateBitcoinOverTor()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/.${network}/${network}.conf | grep -c "${network}.conf")
  if [ ${btcExists} -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTor

    sudo chmod 777 /home/bitcoin/.${network}/${network}.conf
    echo "Adding Tor config to the the ${network}.conf ..."
    sudo sed -i "s/^torpassword=.*//g" /home/bitcoin/.${network}/${network}.conf
    echo "onlynet=onion" >> /home/bitcoin/.${network}/${network}.conf
    echo "proxy=127.0.0.1:9050" >> /home/bitcoin/.${network}/${network}.conf
    echo "main.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "test.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "dnsseed=0" >> /home/bitcoin/.${network}/${network}.conf
    echo "dns=0" >> /home/bitcoin/.${network}/${network}.conf

    # remove empty lines
    sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
    sudo chmod 664 /home/bitcoin/.${network}/${network}.conf

    # copy new bitcoin.conf to admin user for cli access
    sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
    sudo chown admin:admin /home/admin/.${network}/${network}.conf

  else
    echo "BTC config does not found (yet) -  try with 'tor.network.sh btcconf-on' again later"
  fi
}

deactivateBitcoinOverTor()
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
[ -f "/home/admin/raspiblitz.info" ] && source /home/admin/raspiblitz.info
[ -f "/mnt/hdd/raspiblitz.conf" ] && source /mnt/hdd/raspiblitz.conf

torActive=$(sudo systemctl is-active tor@default | grep -c "active")
curl --socks5 127.0.0.1:9050 --socks5-hostname 127.0.0.1:9050 -m 5 -s https://check.torproject.org/api/ip | grep -q "\"IsTor\":true" && torFunctional=1

# if started with status
if [ "$1" = "status" ]; then
  if [ "${runBehindTor}" = "on" ]; then
    echo "torEnabled=1"
  else
    echo "torEnabled=0"
  fi
  echo "torActive=${torActive}"
  echo "torFunctional=${torFunctional}"
  echo "config='${torrc}'"
  exit 0
fi

# if started with btcconf-on
[ "$1" = "btcconf-on" ] && { activateBitcoinOverTor; exit 0; }

# if started with btcconf-off
[ "$1" = "btcconf-off" ] && { deactivateBitcoinOverTor; exit 0; }

# add default value to raspi config if needed
checkTorEntry=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "runBehindTor")
[ ${checkTorEntry} -eq 0 ] && echo "runBehindTor=off" >> /mnt/hdd/raspiblitz.conf

# location of tor config
# make sure /etc/tor exists
sudo mkdir /etc/tor 2>/dev/null

if [ "$1" != "update" ]; then
  # stop services (if running)
  echo "making sure services are not running"
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl stop ${network}d 2>/dev/null
  sudo systemctl stop tor@default 2>/dev/null
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# switching Tor ON"

  # make sure the network was set (by sourcing raspiblitz.conf)
  if [ ${#network} -eq 0 ]; then
    echo "!! FAIL - unknown network due to missing /mnt/hdd/raspiblitz.conf"
    echo "# switching Tor config on for RaspiBlitz services is just possible after basic hdd/ssd setup"
    echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /mnt/hdd/raspiblitz.conf

  # Install Tor
  sudo apt install -y tor torsocks nyx python3-stem obfs4proxy apt-transport-tor

  # Configuring Tor with the pluggable transports
  (sudo mv /usr/local/bin/tor* /usr/bin) 2> /dev/null
  sudo chmod a+x /usr/share/tor/geoip*
  # Copy not moving!
  (sudo cp /usr/share/tor/geoip* /usr/bin) 2> /dev/null
  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/obfs4proxy
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@default.service
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@.service

  ## Install Snowflake
  sudo rm -rf ~/downloads/snowflake
  git clone https://github.com/keroserene/snowflake.git ~/downloads/snowflake
  if [ -d ~/downloads/snowflake ]; then
    echo -e "${WHITE}[!] COULDN'T CLONE THE SNOWFLAKE REPOSITORY!${NOCOLOR}"
    echo -e "${RED}[+] The Snowflake repository may be blocked or offline!${NOCOLOR}"
    echo -e "${RED}[+] Please try again later and if the problem persists, please report it${NOCOLOR}"
  else
    git -C ~/downloads/snowflake checkout "${snowflake_commit_hash}"
  fi

  bash /home/admin/config.scripts/bonus.go.sh
  export GO111MODULE="on"
  cd ~/downloads/snowflake/proxy
  go get
  go build
  sudo cp proxy /usr/bin/snowflake-proxy
  cd ~/downloads/snowflake/client
  go get
  go build
  sudo cp client /usr/bin/snowflake-client
  cd ~
  sudo rm -rf ~/downloads/snowflake

  # create tor data directory if it not exist
  if [ ! -d "/mnt/hdd/tor" ]; then
    echo "# - creating tor data directory"
    sudo mkdir -p /mnt/hdd/tor
    sudo mkdir -p /mnt/hdd/tor/sys
  else
    echo "# - tor data directory exists"
  fi
  # make sure its the correct owner
  sudo chmod -R 700 /mnt/hdd/tor
  sudo chown -R debian-tor:debian-tor /mnt/hdd/tor

  # create tor config .. if not exists or is old
  isTorConfigOK=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c "Bitcoin")
  if [ ${isTorConfigOK} -eq 0 ]; then
    echo "# - updating Tor config ${torrc}"
    cat > ./torrc <<EOF
### torrc for tor@default
### See 'man tor', or https://www.torproject.org/docs/tor-manual.html

DataDirectory /mnt/hdd/tor/sys
PidFile /mnt/hdd/tor/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file /mnt/hdd/tor/notice.log
Log info file /mnt/hdd/tor/info.log

RunAsDaemon 1
ControlPort 9051
SocksPort 9050
ExitRelay 0
CookieAuthentication 1
CookieAuthFileGroupReadable 1

# NOTE: Bitcoin onion private key at /mnt/hdd/lnd/onion_v3_private_key. Delete the priv key and restart bitcoind to renew the advertised address.
# NOTE: LND onion private key at /mnt/hdd/lnd/v3_onion_private_key

# Hidden Service for WEB ADMIN INTERFACE
HiddenServiceDir /mnt/hdd/tor/web80/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Hidden Service for DEBUG LOGS
HiddenServiceDir /mnt/hdd/tor/debuglogs/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:6969

# Hidden Service for LND RPC
HiddenServiceDir /mnt/hdd/tor/lndrpc10009/
HiddenServiceVersion 3
HiddenServicePort 10009 127.0.0.1:10009

# Hidden Service for LND REST
HiddenServiceDir /mnt/hdd/tor/lndrest8080/
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080
EOF
    sudo rm $torrc
    sudo mv ./torrc $torrc
    sudo chmod 644 $torrc
    sudo chown -R debian-tor:debian-tor /var/run/tor/ 2>/dev/null
    echo

    sudo mkdir -p /etc/systemd/system/tor@default.service.d
    sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-/mnt/hdd/tor
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
EOF

  else
    echo "# - Tor config ${torrc} is already updated"
  fi

  # ACTIVATE TOR SERVICE
  echo "*** Enable Tor Service ***"
  sudo systemctl daemon-reload
  sudo systemctl enable tor@default
  echo

  # ACTIVATE BITCOIN OVER TOR (function call)
  activateBitcoinOverTor

  # ACTIVATE APPS OVER TOR
  source /mnt/hdd/raspiblitz.conf 2>/dev/null
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

  echo "OK - Tor is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
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

  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || [ "${lnd}" == "1" ]; then
    echo "# *** Removing Tor from LND Mainnet ***"
    sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/lnd/lnd.conf
    sudo sed -i '/^tor\..*/d' /mnt/hdd/lnd/lnd.conf
    sudo systemctl restart lnd
  fi

  if [ "${tlnd}" == "on" ] || [ "${tlnd}" == "1" ]; then
    echo "# *** Removing Tor from LND Testnet ***"
    sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/lnd/tlnd.conf
    sudo sed -i '/^tor\..*/d' /mnt/hdd/lnd/tlnd.conf
    sudo systemctl restart tlnd
  fi

  if [ "${slnd}" == "on" ] || [ "${slnd}" == "1" ]; then
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

  if [ "$2" == "clear" ]; then
      echo "# *** Uninstall Tor & Delete Data ***"
      sudo rm -r /mnt/hdd/tor 2>/dev/null
      sudo apt remove tor nyx -y
  fi

  echo "# needs reboot to activate new setting"
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  # as in https://2019.www.torproject.org/docs/debian#source
  echo "# Install the dependencies"
  sudo apt update
  sudo apt install -y build-essential fakeroot devscripts
  sudo apt build-dep -y tor deb.torproject.org-keyring
  rm -rf /home/admin/download/debian-packages
  mkdir -p /home/admin/download/debian-packages
  cd /home/admin/download/debian-packages
  echo "# Building Tor from the source code ..."
  apt source tor
  cd tor-*
  debuild -rfakeroot -uc -us
  cd ..
  echo "# Stopping the tor.service before updating"
  sudo systemctl stop tor
  echo "# Update ..."
  sudo dpkg -i tor_*.deb
  echo "# Starting the tor.service "
  sudo systemctl start tor
  echo "# Installed $(tor --version)"
  if [ $(systemctl status lnd | grep -c "active (running)") -gt 0 ];then
    echo "# LND needs to restart"
    sudo systemctl restart lnd
    sudo systemctl restart tlnd 2>/dev/null
    sudo systemctl restart slnd 2>/dev/null
    sleep 10
    lncli unlock
  fi
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may needs reboot to run normal again"
exit 1

