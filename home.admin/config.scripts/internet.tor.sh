#!/bin/bash

# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch TOR on or off"
 echo "internet.tor.sh [status|on|off|prepare|btcconf-on|btcconf-off|lndconf-on]"
 exit 1
fi

torrc="/etc/tor/torrc"

baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
isArmbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
fi
if [ ${isArmbian} -gt 0 ]; then
  baseImage="armbian"
fi 
if [ ${isUbuntu} -gt 0 ]; then
baseImage="ubuntu"
fi
if [ ${isDietPi} -gt 0 ]; then
  baseImage="dietpi"
fi
if [ "${baseImage}" = "?" ]; then
  cat /etc/os-release 2>/dev/null
  echo "# !!! FAIL !!!"
  echo "# Base Image cannot be detected or is not supported."
  echo "error='unknown os'"
  exit 1
else
  echo "os='${baseImage}'"
fi

# function: install keys & sources
prepareTorSources()
{
    # Prepare for TOR service
    echo "*** INSTALL TOR REPO ***"
    echo ""

    echo "*** Install dirmngr ***"
    sudo apt install dirmngr -y
    echo ""

    echo "*** Adding KEYS deb.torproject.org ***"
    torKeyAvailable=$(sudo gpg --list-keys | grep -c "A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89")
    echo "torKeyAvailable=${torKeyAvailable}"
    if [ ${torKeyAvailable} -eq 0 ]; then
      curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
      sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
      echo "OK"
    else
      echo "TOR key is available"
    fi
    echo ""
 
    echo "*** Adding Tor Sources to sources.list ***"
    torSourceListAvailable=$(sudo cat /etc/apt/sources.list | grep -c 'https://deb.torproject.org/torproject.org')
    echo "torSourceListAvailable=${torSourceListAvailable}"  
    if [ ${torSourceListAvailable} -eq 0 ]; then
      echo "Adding TOR sources ..."
      if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "armbian" ] || [ "${baseImage}" = "dietpi" ]; then
        echo "deb https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
        echo "deb-src https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
      elif [ "${baseImage}" = "ubuntu" ]; then
        echo "deb https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list
        echo "deb-src https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list    
      fi
      echo "OK"
    else
      echo "TOR sources are available"
    fi
    echo ""
}

activateBitcoinOverTOR()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/.${network}/${network}.conf | grep -c "${network}.conf")
  if [ ${btcExists} -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTOR

    echo "Addding TOR config ..."
    sudo chmod 777 /home/bitcoin/.${network}/${network}.conf
    echo "onlynet=onion" >> /home/bitcoin/.${network}/${network}.conf
    echo "proxy=127.0.0.1:9050" >> /home/bitcoin/.${network}/${network}.conf
    echo "main.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "test.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "dnsseed=0" >> /home/bitcoin/.${network}/${network}.conf
    echo "dns=0" >> /home/bitcoin/.${network}/${network}.conf
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    echo "torpassword=$PASSWORD_B" >> /home/bitcoin/.${network}/${network}.conf
    if [ "${network}" = "bitcoin" ]; then
      # adding some bitcoin onion nodes to connect to to make connection easier
      echo "main.addnode=fno4aakpl6sg6y47.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=toguvy5upyuctudx.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=ndndword5lpb7eex.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=6m2iqgnqjxh7ulyk.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=5tuxetn7tar3q5kp.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=juo4oneckybinerq.onion" >> /home/bitcoin/.${network}/${network}.conf
    fi
    sudo chmod 444 /home/bitcoin/.${network}/${network}.conf

    # copy new bitcoin.conf to admin user for cli access
    sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
    sudo chown admin:admin /home/admin/.${network}/${network}.conf

  else
    echo "BTC config does not found (yet) -  try with 'internet.tor.sh btcconf-on' again later" 
  fi

}

deactivateBitcoinOverTOR()
{
  # always make sure also to remove old settings
  sudo sed -i "s/^onlynet=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^torpassword=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^proxy=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dnsseed=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dns=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
  sudo cp /home/bitcoin/.${network}/${network}.conf /home/admin/.${network}/${network}.conf
  sudo chown admin:admin /home/admin/.${network}/${network}.conf
}

activateLndOverTOR()
{
  echo "*** Putting LND behind TOR ***"

  lndExists=$(sudo ls /etc/systemd/system/lnd.service | grep -c "lnd.service")
  if [ ${lndExists} -gt 0 ]; then

    # modify LND service
    echo "Make sure LND is disabled"
    sudo systemctl disable lnd 2>/dev/null

    echo "editing /etc/systemd/system/lnd.service"
    sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*/ExecStart=\/usr\/local\/bin\/lnd --tor\.active --tor\.streamisolation --tor\.v3 --listen=127\.0\.0\.1\:9735 \${lndExtraParameter}/g" /etc/systemd/system/lnd.service

    # check if "tor.password" exists
    valueExists=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'tor.password=')
    if [ ${valueExists} -eq 0 ]; then
        echo "Adding tor config defaults to /mnt/hdd/lnd/lnd.conf"
        PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
        sudo -u bitcoin tee -a /mnt/hdd/lnd/lnd.conf >/dev/null <<EOF
[Tor]
tor.password=$PASSWORD_B
EOF
    fi

    echo "Enable LND again"
    sudo systemctl enable lnd
    echo "OK"
    echo ""

  else
    echo "LND service not found (yet) -  try with 'internet.tor.sh lndconf-on' again later" 
  fi

}

# if started with prepare 
if [ "$1" = "prepare" ] || [ "$1" = "-prepare" ]; then
  prepareTorSources
  exit 0
fi

# check and load raspiblitz config
# to know which network is running
if [ -f "/home/admin/raspiblitz.info" ]; then
  source /home/admin/raspiblitz.info
fi

if [ -f "/mnt/hdd/raspiblitz.conf" ]; then
  source /mnt/hdd/raspiblitz.conf
fi

# make sure the network was set (by sourcing raspiblitz.conf)
if [ ${#network} -eq 0 ]; then
 echo "FAIL - unknwon network due to missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi

# if started with status
if [ "$1" = "status" ]; then
  # is Tor activated
  if [ "${runBehindTor}" == "on" ]; then
    echo "activated=1"
  else
    echo "activated=0"
  fi
  echo "config='${torrc}'"
  exit 0
fi

# if started with btcconf-on 
if [ "$1" = "btcconf-on" ]; then
  activateBitcoinOverTOR
  exit 0
fi

# if started with btcconf-off
if [ "$1" = "btcconf-off" ]; then
  deactivateBitcoinOverTOR
  exit 0
fi

# if started with lndconf-on
if [ "$1" = "lndconf-on" ]; then
  activateLndOverTOR
  exit 0
fi

# add default value to raspi config if needed
checkTorEntry=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "runBehindTor")
if [ ${checkTorEntry} -eq 0 ]; then
  echo "runBehindTor=off" >> /mnt/hdd/raspiblitz.conf
fi

# location of TOR config
# make sure /etc/tor exists
sudo mkdir /etc/tor 2>/dev/null

# stop services (if running)
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null
sudo systemctl stop ${network}d 2>/dev/null
sudo systemctl stop tor@default 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the TOR ON"

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /mnt/hdd/raspiblitz.conf

  # check if TOR was already installed and is funtional
  echo ""
  echo "*** Check if TOR service is functional ***"
  torRunning=$(curl --connect-timeout 10 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org 2>/dev/null | grep "Congratulations. This browser is configured to use Tor." -c)
  if [ ${torRunning} -gt 0 ]; then
    clear
    echo "You are all good - TOR is already running."
    echo ""
    exit 0
  else
    echo "TOR not running ... proceed with switching to TOR."
    echo ""
  fi

  # check if TOR package is installed
  packageInstalled=$(dpkg -s tor-arm | grep -c 'Status: install ok')
  if [ ${packageInstalled} -eq 0 ]; then

    # calling function from above
    prepareTorSources

    echo "*** Updating System ***"
    sudo apt update -y
    echo ""

    echo "*** Install Tor & NYX ***"
    sudo apt install tor tor-arm -y

    echo ""
    echo "*** Tor Config ***"
    sudo mkdir -p /mnt/hdd/tor
    sudo mkdir -p /mnt/hdd/tor/sys
    sudo chmod -R 700 /mnt/hdd/tor
    sudo chown -R debian-tor:debian-tor /mnt/hdd/tor
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    HASHED_PASSWORD=$(sudo -u debian-tor tor --hash-password "$PASSWORD_B")

    cat > ./torrc <<EOF
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

HashedControlPassword $HASHED_PASSWORD

# Hidden Service for WEB ADMIN INTERFACE
HiddenServiceDir /mnt/hdd/tor/web80/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Hidden Service for BITCOIN
HiddenServiceDir /mnt/hdd/tor/bitcoin8332/
HiddenServiceVersion 3
HiddenServicePort 8332 127.0.0.1:8332
 
# Hidden Service for LND (incoming connections)
HiddenServiceDir /mnt/hdd/tor/lnd9735
HiddenServiceVersion 3
HiddenServicePort 9735 127.0.0.1:9735

# Hidden Service for LND RPC
HiddenServiceDir /mnt/hdd/tor/lndrpc10009/
HiddenServiceVersion 3
HiddenServicePort 10009 127.0.0.1:10009

# Hidden Service for LND RPC (v2Fallback)
HiddenServiceDir /mnt/hdd/tor/lndrpc10009fallback/
HiddenServiceVersion 2
HiddenServicePort 10009 127.0.0.1:10009

# Hidden Service for LND REST
HiddenServiceDir /mnt/hdd/tor/lndrest8080/
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080

# Hidden Service for LND REST (v2Fallback)
HiddenServiceDir /mnt/hdd/tor/lndrest8080fallback/
HiddenServiceVersion 2
HiddenServicePort 8080 127.0.0.1:8080

# NOTE: bitcoind get tor service automatically - see /mnt/hdd/bitcoin for onion key
EOF
    sudo rm $torrc
    sudo mv ./torrc $torrc
    sudo chmod 644 $torrc
    sudo chown -R debian-tor:debian-tor /var/run/tor/ 2>/dev/null
    echo ""

    sudo mkdir -p /etc/systemd/system/tor@default.service.d
    sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generate by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-/mnt/hdd/tor
EOF

  else
    echo "TOR package/service is installed and was prepared earlier .. just activating again"
  fi

  # ACTIVATE TOR SERVICE
  echo "*** Enable TOR Service ***"
  sudo systemctl daemon-reload
  sudo systemctl enable tor@default
  echo ""

  # ACTIVATE BITCOIN OVER TOR (function call)
  activateBitcoinOverTOR

  # ACTIVATE LND OVER TOR (function call)
  activateLndOverTOR

  # ACTIVATE APPS OVER TOR
  source /mnt/hdd/raspiblitz.conf 2>/dev/null
  if [ "${BTCRPCexplorer}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh btc-rpc-explorer 80 3002
  fi
  if [ "${rtlWebinterface}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh RTL 80 3002 443 3003
  fi
  if [ "${BTCPayServer}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh btcpay 80 23002 443 23003
  fi
  if [ "${ElectRS}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh electrs 50002 50002 50001 50001
  fi
  if [ "${LNBits}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh lnbits 80 5002 443 5003
  fi
  if [ "${thunderhub}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh thunderhub 80 3012 443 3013
  fi
  if [ "${specter}" = "on" ]; then
    # specter makes only sense to be served over https
    /home/admin/config.scripts/internet.hiddenservice.sh cryptoadvance-specter 443 25441
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

  sudo systemctl restart tor@default

  echo "OK - TOR is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching TOR OFF"

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=off/g" /mnt/hdd/raspiblitz.conf

  # disable TOR service
  echo "*** Disable TOR service ***"
  sudo systemctl disable tor@default
  echo ""

  # DEACTIVATE BITCOIN OVER TOR (function call)
  deactivateBitcoinOverTOR
  echo ""

  echo "*** Removing TOR from LND ***"
  sudo systemctl disable lnd
  echo "editing /etc/systemd/system/lnd.service"
  sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*/ExecStart=\/usr\/local\/bin\/lnd --externalip=\${publicIP}:\${lndPort} \${lndExtraParameter}/g" /etc/systemd/system/lnd.service
  sudo sed -i '/\[Tor\]*/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^tor.password=*/d' /mnt/hdd/lnd/lnd.conf

  sudo systemctl enable lnd
  echo "OK"
  echo ""

  echo "*** Stop TOR service ***"
  sudo systemctl stop tor@default
  echo ""

  if [ "$2" == "clear" ]; then
      echo "*** Deinstall Tor & Delete Data ***"
       sudo apt remove tor tor-arm -y
       sudo rm -r /mnt/hdd/tor 2>/dev/null
  fi

  echo "needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may needs reboot to run normal again"
exit 1
