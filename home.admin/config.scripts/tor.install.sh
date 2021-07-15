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
 echo "tor.network-install.sh [status|on|btcconf-on|lndconf-on]"
 exit 1
fi

# include lib
. /home/admin/config.scripts/tor.functions.lib


activateBitcoinOverTor()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/.${network}/${network}.conf | grep -c "${network}.conf")
  if [ ${btcExists} -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTor

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
    echo "BTC config does not found (yet) -  try with 'tor.on.sh btcconf-on' again later"
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


activateLndOverTor()
{
  echo "*** Putting LND behind Tor ***"

  lndExists=$(sudo ls /etc/systemd/system/lnd.service | grep -c "lnd.service")
  if [ ${lndExists} -gt 0 ]; then

    # deprecate 'torpassword='
    sudo sed -i '/\[Tor\]*/d' /mnt/hdd/lnd/lnd.conf
    sudo sed -i '/^tor.password=*/d' /mnt/hdd/lnd/lnd.conf

    # modify LND service
    echo "# Make sure LND is disabled"
    sudo systemctl disable lnd 2>/dev/null

    echo "# Editing /etc/systemd/system/lnd.service"
    sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*/ExecStart=\/usr\/local\/bin\/lnd \
    --tor\.active --tor\.streamisolation --tor\.v3 --tor\.socks=${DEFAULT_SOCKS_PORT} --tor\.control=${DEFAULT_CONTROL_PORT} \
    --listen=127\.0\.0\.1\:9735 \${lndExtraParameter}/g" /etc/systemd/system/lnd.service

    echo "# Enable LND again"
    sudo systemctl enable lnd
    echo "# OK"
    echo

  else
    echo "# LND service not found (yet) - try with 'tor.on.sh lndconf-on' again later"
  fi
}


# check and load raspiblitz config
# to know which network is running
if [ -f "/home/admin/raspiblitz.info" ]; then
  source /home/admin/raspiblitz.info
fi

if [ -f "${CONF}" ]; then
  source ${CONF}
fi

# if started with status
if [ "$1" = "status" ]; then
  # is Tor activated
  if [ "${runBehindTor}" == "on" ]; then
    echo "activated=1"
  else
    echo "activated=0"
  fi

  echo "config='${TORRC}'"
  exit 0
fi

# if started with btcconf-on
if [ "$1" = "btcconf-on" ]; then
  activateBitcoinOverTor
  exit 0
fi

# if started with lndconf-on
if [ "$1" = "lndconf-on" ]; then
  activateLndOverTor
  exit 0
fi

# add default value to raspi config if needed
checkTorEntry=$(sudo cat ${CONF} | grep -c "runBehindTor")
if [ ${checkTorEntry} -eq 0 ]; then
  echo "runBehindTor=off" >> ${CONF}
fi

# location of Tor config
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
    echo "!! FAIL - unknown network due to missing ${CONF}"
    echo "# switching Tor config on for RaspiBlitz services is just possible after basic hdd/ssd setup"
    echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" ${CONF}

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

  # 7. Configuring Tor with the pluggable transports
  sleep 10
  clear
  echo -e "${RED}[+] Step 7: Configuring Tor with the pluggable transports....${NOCOLOR}"
  sudo cp /usr/share/tor/geoip* /usr/bin
  sudo chmod a+x /usr/bin/geoip*
  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/obfs4proxy
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@default.service
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@.service

  # Additional installation for GO
  bash /home/admin/config.scripts/bonus.go.sh on
  export GO111MODULE="on"

  # Do NOT use torproject.org domain cause they could be blocked
  # they can be used later when tor is functioning, but now is the setup
  # paths saved here for those who want, it is always the same version anyway

  # SNOWFLAKE
  #git clone https://git.torproject.org/pluggable-transports/snowflake.git
  git clone https://github.com/keroserene/snowflake.git
  cd /home/admin/snowflake/proxy
  go get
  go build
  sudo cp proxy /usr/bin/snowflake-proxy
  cd /home/admin/snowflake/client
  go get
  go build
  sudo cp client /usr/bin/snowflake-client

  cd /home/admin

  # OBFS4
  #git clone https://gitweb.torproject.org/pluggable-transports/obfs4.git/
  git clone https://salsa.debian.org/pkg-privacy-team/obfs4proxy.git
  cd /home/admin/obfs4proxy/
  go build -o obfs4proxy/obfs4proxy ./obfs4proxy
  sudo cp ./obfs4proxy/obfsproxy /usr/local/bin/obfs4proxy/obfsproxy

  cd /home/admin

  sudo rm -rf obfs4proxy
  sudo rm -rf snowflake
  sudo rm -rf go*

  # remove GO
  bash /home/admin/config.scripts/bonus.go.sh off

  # Install requirements to request bridges from the database
  # https://github.com/radio24/TorBox/blob/master/requirements.txt
  sudo pip3 -r install /home/admin/tor.requirements.txt

  # install package just in case it was deinstalled
  packageInstalled=$(dpkg -s tor-arm | grep -c 'Status: install ok')
  if [ ${packageInstalled} -eq 0 ]; then
    sudo apt install tor nyx torsocks -y
  fi

  # create tor data directory if it not exist
  if [ ! -d "${DATA_DIR}" ]; then
    echo "# - creating tor data directory"
    sudo mkdir -p ${DATA_DIR}
    sudo mkdir -p ${DATA_DIR}/sys
  else
    echo "# - tor data directory exists"
  fi
  # make sure its the correct owner
  set_owner_permission

  # create tor config .. if not exists or is old
  isTorConfigOK=$(sudo cat ${TORRC} 2>/dev/null | grep -c "Bitcoin")
  if [ ${isTorConfigOK} -eq 0 ]; then
    echo "# - updating Tor config ${TORRC}"
    cat > ./torrc <<EOF
### torrc for tor@default
### See 'man tor', or https://www.torproject.org/docs/tor-manual.html

DataDirectory ${DATA_DIR}/sys
PidFile ${DATA_DIR}/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file ${DATA_DIR}/notice.log
Log info file ${DATA_DIR}/info.log

RunAsDaemon 1
ControlPort 9051
SocksPort 9050
ExitRelay 0
CookieAuthentication 1
CookieAuthFileGroupReadable 1

# Hidden Service for WEB ADMIN INTERFACE
HiddenServiceDir ${DATA_DIR}/web80/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Hidden Service for LND RPC
HiddenServiceDir ${DATA_DIR}/lndrpc10009/
HiddenServiceVersion 3
HiddenServicePort 10009 127.0.0.1:10009

# Hidden Service for LND REST
HiddenServiceDir ${DATA_DIR}/lndrest8080/
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080
EOF
    sudo rm ${TORRC}
    sudo mv ./torrc ${TORRC}
    sudo chmod 644 ${TORRC}
    sudo chown -R debian-tor:debian-tor /var/run/tor/ 2>/dev/null
    echo ""

    sudo mkdir -p /etc/systemd/system/tor@default.service.d
    sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-${DATA_DIR}
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
EOF

  else
    echo "# - Tor config ${TORRC} is already updated"
  fi

  # ACTIVATE Tor SERVICE
  echo "*** Enable Tor Service ***"
  sudo systemctl daemon-reload
  sudo systemctl enable tor@default
  echo ""

  # ACTIVATE BITCOIN OVER Tor (function call)
  activateBitcoinOverTor

  # ACTIVATE LND OVER Tor (function call)
  activateLndOverTor

  # ACTIVATE APPS OVER Tor
  source ${CONF} 2>/dev/null

  # for organizatation, FROM_PORT_2 is the TLS one

  if [ "${sshTor}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} ssh 22 22
    if [ "${sshTorOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on ssh
    fi
  fi

  if [ "${BTCRPCexplorer}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} btc-rpc-explorer 80 3002
    if [ "${BTCRPCexplorerOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on btc-rpc-explorer
    fi
  fi

  if [ "${rtlWebinterface}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} RTL 80 3002 443 3003
    if [ "${rtlWebinterfaceOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on RTL
    fi
  fi

  if [ "${BTCPayServer}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} btcpay 80 23002 443 23003
    if [ "${BTCPayServerOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on btcpay
    fi
  fi

  if [ "${ElectRS}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} electrs 50001 50001 50002 50002
  fi

  if [ "${LNBits}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} lnbits 80 5002 443 5003
    if [ "${LNBitsOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on lnbits
    fi
  fi

  if [ "${thunderhub}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} thunderhub 80 3012 443 3013
    if [ "${thunderhubAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on thunderhub
    fi
  fi

  if [ "${specter}" = "on" ]; then
    # specter makes only sense to be served over https
    ${ONION_SERVICE_SCRIPT} cryptoadvance-specter 443 25441
    if [ "${specterOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on cryptoadvance-specter
    fi
  fi

  if [ "${sphinxrelay}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} sphinxrelay 80 3302 443 3303
    toraddress=$(sudo cat${DATA_DIR}/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
  fi

    # get Tor address and store it readable for sphixrelay user
    toraddress=$(sudo cat ${DATA_DIR}/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"

  echo "Setup logrotate"
  # add logrotate config for modified Tor dir on ext. disk
  sudo tee /etc/logrotate.d/raspiblitz-tor >/dev/null <<EOF
${DATA_DIR}/*log {
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
