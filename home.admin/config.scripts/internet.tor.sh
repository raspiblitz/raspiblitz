#!/bin/bash

# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

# INFO
# --------------------
# basic install of Tor is done by the build script now .. on/off will just switch service on/off
# also thats where the sources are set and the preparation is done

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to switch Tor on or off"
 echo "internet.tor.sh [status|on|off|btcconf-on|btcconf-off|lndconf-on|update]"
 exit 1
fi

torrc="/etc/tor/torrc"

activateBitcoinOverTOR()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/.${network}/${network}.conf | grep -c "${network}.conf")
  if [ ${btcExists} -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTOR

    echo "# Make sure the user bitcoin is in the debian-tor group"
    sudo usermod -a -G debian-tor bitcoin
    sudo chmod 777 /home/bitcoin/.${network}/${network}.conf
    echo "Adding Tor config to the the ${network}.conf ..."
    # deprecate 'torpassword='
    sudo sed -i "s/^torpassword=.*//g" /home/bitcoin/.${network}/${network}.conf
    echo "onlynet=onion" >> /home/bitcoin/.${network}/${network}.conf
    echo "proxy=127.0.0.1:9050" >> /home/bitcoin/.${network}/${network}.conf
    echo "main.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "test.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "dnsseed=0" >> /home/bitcoin/.${network}/${network}.conf
    echo "dns=0" >> /home/bitcoin/.${network}/${network}.conf
    if [ "${network}" = "bitcoin" ]; then
      # adding some bitcoin onion nodes to connect to to make connection easier
      echo "main.addnode=ira7kqcbff52wofoong2dieh2xlvmw4e7ya3znsqn7wivn6armetvrqd.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=xlpi353v7ia5b73msynr7tmddgxoco7n2r2bljt5txpv6bpzzphkreyd.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=ccjrb6va3j6re4lg2lerlt6wyvlb4tod7qbe7rwiouuapb7etvterxyd.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=s7m4mnd6bokujhywsocxibispktruormushdroeaeqeb3imvztfs3vid.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=ldvhlpsrvspquqnl3gutz7grfu5lb3m2dgnezpl3tlkxgpoiw2g5mzid.onion" >> /home/bitcoin/.${network}/${network}.conf
      echo "main.addnode=gliovxxzyy2rkwaoz25khf6oa64c3csqzjn3t6dodsjuf34w6a6ktsyd.onion" >> /home/bitcoin/.${network}/${network}.conf
    fi
    # remove empty lines
    sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
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

activateLndOverTOR()
{
  echo "*** Putting LND behind Tor ***"

  lndExists=$(sudo ls /etc/systemd/system/lnd.service | grep -c "lnd.service")
  if [ ${lndExists} -gt 0 ]; then

    # deprecate 'torpassword='
    sudo sed -i '/\[Tor\]*/d' /mnt/hdd/lnd/lnd.conf
    sudo sed -i '/^tor.password=*/d' /mnt/hdd/lnd/lnd.conf

    # lnd-tor instance
    NODENAME="lnd"
    SOCKSPORT=9070
    CONTROLPORT=$((SOCKSPORT+1))
    echo "# Creating a dedicated Tor instance for $NODENAME"
    # https://www.torservers.net/wiki/setup/server#multiple_tor_processes
   
    sudo tor-instance-create $NODENAME

    echo "# Make sure the user bitcoin is in the _tor-$NODENAME group"
    sudo usermod -a -G _tor-$NODENAME bitcoin

  # create tor data directory if it not exist
  if [ ! -d "/mnt/hdd/tor-$NODENAME" ]; then
    echo "# - creating tor data directory"
    sudo mkdir -p /mnt/hdd/tor-$NODENAME
    sudo mkdir -p /mnt/hdd/tor-$NODENAME/sys
  else
    echo "# - /mnt/hdd/tor-$NODENAME data directory exists"
  fi
  # make sure its the correct owner
  sudo chmod -R 700 /mnt/hdd/tor-$NODENAME
  sudo chown -R _tor-$NODENAME:_tor-$NODENAME /mnt/hdd/tor-$NODENAME

  echo "
DataDirectory /mnt/hdd/tor-$NODENAME/sys
PidFile /mnt/hdd/tor-$NODENAME/sys/tor.pid
SocksPort $SOCKSPORT
ControlPort $CONTROLPORT
CookieAuthentication 1
CookieAuthFileGroupReadable 1
SafeLogging 0
Log notice stdout
Log notice file /mnt/hdd/tor-$NODENAME/notice.log
Log info file /mnt/hdd/tor-$NODENAME/info.log
" | sudo tee /etc/tor/instances/$NODENAME/torrc
    sudo chmod 644 /etc/tor/instances/$NODENAME/torrc

  sudo mkdir -p /etc/systemd/system/tor@$NODENAME.service.d
  sudo tee /etc/systemd/system/tor@$NODENAME.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-/mnt/hdd/tor-$NODENAME
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
EOF

  echo "Setup logrotate"
  # add logrotate config for modified Tor dir on ext. disk
  sudo tee /etc/logrotate.d/raspiblitz-tor-$NODENAME >/dev/null <<EOF
/mnt/hdd/tor-$NODENAME/*log {
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
    sudo systemctl daemon-reload
    sudo systemctl enable tor@$NODENAME
    sudo systemctl start tor@$NODENAME
    
    # config for lnd self-test
    echo "
strict_chain
proxy_dns 
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 	127.0.0.1 $SOCKSPORT
" | sudo tee /etc/proxychains.$NODENAME.conf

    # modify LND service
    echo "# Make sure LND is disabled"
    sudo systemctl disable lnd 2>/dev/null

    echo "# Editing /etc/systemd/system/lnd.service"
    sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*\
/ExecStart=\/usr\/local\/bin\/lnd --tor\.active --tor\.streamisolation --tor\.v3 --tor\.socks=$SOCKSPORT --tor\.control=$CONTROLPORT --listen=127\.0\.0\.1\:9735 \${lndExtraParameter}/g" \
    /etc/systemd/system/lnd.service

    echo "# Enable LND again"
    sudo systemctl enable lnd
    echo "# OK"
    echo 

  else
    echo "# LND service not found (yet) - try with 'internet.tor.sh lndconf-on' again later" 
  fi
}

# check and load raspiblitz config
# to know which network is running
if [ -f "/home/admin/raspiblitz.info" ]; then
  source /home/admin/raspiblitz.info
fi

if [ -f "/mnt/hdd/raspiblitz.conf" ]; then
  source /mnt/hdd/raspiblitz.conf
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

  # *** CURL TOR PROXY ***
  # see https://github.com/rootzoll/raspiblitz/issues/1341
  #echo "socks5-hostname localhost:9050" > .curlrc.tmp
  #sudo cp ./.curlrc.tmp /root/.curlrc
  #sudo chown root:root /home/admin/.curlrc
  #sudo cp ./.curlrc.tmp /home/pi/.curlrc
  #sudo chown pi:pi /home/pi/.curlrc
  #sudo cp ./.curlrc.tmp /home/admin/.curlrc
  #sudo chown admin:admin /home/admin/.curlrc
  #rm .curlrc.tmp

  # make sure the network was set (by sourcing raspiblitz.conf)
  if [ ${#network} -eq 0 ]; then
    echo "!! FAIL - unknown network due to missing /mnt/hdd/raspiblitz.conf"
    echo "# switching Tor config on for RaspiBlitz services is just possible after basic hdd/ssd setup"
    echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /mnt/hdd/raspiblitz.conf

  # check if Tor was already installed and is funtional
  echo ""
  echo "*** Check if Tor service is functional ***"
  torRunning=$(curl --connect-timeout 10 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org 2>/dev/null | grep "Congratulations. This browser is configured to use Tor." -c)
  if [ ${torRunning} -gt 0 ]; then
    clear
    echo "You are all good - Tor is already running."
    echo ""
    exit 0
  else
    echo "Tor not running ... proceed with switching to Tor."
    echo ""
  fi

  # install package just in case it was deinstalled
  packageInstalled=$(dpkg -s tor-arm | grep -c 'Status: install ok')
  if [ ${packageInstalled} -eq 0 ]; then
    sudo apt install tor tor-arm torsocks -y
  fi

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
  isTorConfigOK=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c "BITCOIN")
  if [ ${isTorConfigOK} -eq 0 ]; then
    echo "# - updating Tor config ${torrc}"
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
CookieAuthentication 1
CookieAuthFileGroupReadable 1

# Hidden Service for WEB ADMIN INTERFACE
HiddenServiceDir /mnt/hdd/tor/web80/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Hidden Service for BITCOIN RPC (mainnet, testnet, signet)
HiddenServiceDir /mnt/hdd/tor/bitcoin8332/
HiddenServiceVersion 3
HiddenServicePort 8332 127.0.0.1:8332
HiddenServicePort 18332 127.0.0.1:18332
HiddenServicePort 38332 127.0.0.1:38332

# NOTE: since Bitcoin Core v0.21.0 sets up a v3 Tor service automatically 
# see /mnt/hdd/bitcoin for the onion private key - delete and restart bitcoind to reset

# Hidden Service for BITCOIN P2P (v2FallBack for Bisq)
HiddenServiceDir /mnt/hdd/tor/bitcoin8333
HiddenServiceVersion 2
HiddenServicePort 8333 127.0.0.1:8333
 
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
EOF
    sudo rm $torrc
    sudo mv ./torrc $torrc
    sudo chmod 644 $torrc
    sudo chown -R debian-tor:debian-tor /var/run/tor/ 2>/dev/null
    echo ""

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
  if [ "${sphinxrelay}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh sphinxrelay 80 3302 443 3303
    toraddress=$(sudo cat /mnt/hdd/tor/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
  fi

    # get TOR address and store it readable for sphixrelay user
    toraddress=$(sudo cat /mnt/hdd/tor/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"

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

  echo "OK - Tor is now ON"
  echo "needs reboot to activate new setting"
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

  # disable TOR service
  echo "# *** Disable Tor service ***"
  sudo systemctl disable tor@default
  sudo systemctl disable tor@lnd
  echo ""

  # DEACTIVATE BITCOIN OVER TOR (function call)
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
  sudo systemctl stop tor@lnd
  echo ""

  if [ "$2" == "clear" ]; then
      echo "# *** Deinstall Tor & Delete Data ***"
      sudo rm -r /mnt/hdd/tor 2>/dev/null
      sudo apt remove tor tor-arm -y
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
    sleep 10
    lncli unlock
  fi
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may needs reboot to run normal again"
exit 1
