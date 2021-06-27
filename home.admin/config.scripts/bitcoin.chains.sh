#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove parallel chains for Bitcoin Core"
  echo "network.bitcoinchains.sh [on|off] [signet|testnet|mainnet]"
  echo
  exit 1
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ "${CHAIN}" != signet ]&&[ "${CHAIN}" != testnet ]&&[ "${CHAIN}" != mainnet ];then
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  prefix="t"
  bitcoinprefix="test"
  zmqprefix=21  # zmqpubrawblock=21332 zmqpubrawtx=21333
  rpcprefix=1   # rpcport=18332
elif [ ${CHAIN} = signet ];then
  prefix="s"
  bitcoinprefix="signet"
  zmqprefix=23
  rpcprefix=3
elif [ ${CHAIN} = mainnet ];then
  prefix=""
  bitcoinprefix="main"
  zmqprefix=28
  rpcprefix=""
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}bitcoind.service" ];then
    if [ ${CHAIN} != mainnet ];then
      /usr/local/bin/bitcoin-cli -${CHAIN} stop
    else
      /usr/local/bin/bitcoin-cli stop
    fi
    sudo systemctl stop ${prefix}bitcoind
    sudo systemctl disable ${prefix}bitcoind
    if [ ${bitcoinprefix} = signet ];then
      # check for signet service set up by joininbox  
      if [ -f "/etc/systemd/system/signetd.service" ];then
        sudo systemctl stop signetd
        sudo systemctl disable signetd
        echo "# The signetd.service is stopped and disabled"
      fi
    fi
    echo "# Bitcoin Core on ${CHAIN} service is stopped and disabled"
  fi
}

function installParallelService() {
  echo "# Installing Bitcoin Core instance on ${CHAIN}"
  # bitcoin.conf
  if [ ! -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    # add minimal config
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for ${CHAIN}

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass
${bitcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${bitcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/bitcoin.conf
  else
    echo "# /home/bitcoin/.bitcoin/bitcoin.conf is present"
  fi
  
  # make sure rpcbind is correctly configured
  sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "rpcallowip" < /mnt/hdd/${network}/${network}.conf) -gt 0 ];then
    if [ $(grep -c "${bitcoinprefix}.rpcbind=" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
      echo "\
${bitcoinprefix}.rpcbind=127.0.0.1"|\
      sudo tee -a /mnt/hdd/${network}/${network}.conf
    fi
  fi

  # correct rpcport entry
  sudo sed -i s/^rpcport=/main.rpcport=/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "${bitcoinprefix}.rpcport" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
    echo "\
${bitcoinprefix}.rpcport=${rpcprefix}8332"|\
    sudo tee -a /mnt/hdd/${network}/${network}.conf
  fi

  # correct zmq entry
  sudo sed -i s/^zmqpubraw/main.zmqpubraw/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "${bitcoinprefix}.zmqpubrawblock" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
    echo "\
${bitcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${bitcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333"|\
    sudo tee -a /mnt/hdd/${network}/${network}.conf
  fi

  if [ -f /mnt/hdd/lnd/lnd.conf ];then
    echo "# Check mainnet lnd.conf" 
    RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    RPCPSW=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    # it does not pick up main.zmqpubraw entries from bitcoin.conf, need to set manually
    if [ $(grep -c zmqpubrawblock /mnt/hdd/lnd/lnd.conf) -eq 0 ];then 
      echo "
[bitcoind]
bitcoind.rpcuser=$RPCUSER
bitcoind.rpcpass=$RPCPSW
bitcoind.zmqpubrawblock=tcp://127.0.0.1:28332
bitcoind.zmqpubrawtx=tcp://127.0.0.1:28333
"   | sudo tee -a /mnt/hdd/lnd/lnd.conf
    fi
  fi

  # addnode
  if [ ${bitcoinprefix} = signet ];then
    if [ $(grep -c "${bitcoinprefix}.addnode" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
      echo "\
signet.addnode=s7fcvn5rblem7tiquhhr7acjdhu7wsawcph7ck44uxyd6sismumemcyd.onion:38333
signet.addnode=6megrst422lxzsqvshkqkg6z2zhunywhyrhy3ltezaeyfspfyjdzr3qd.onion:38333
signet.addnode=jahtu4veqnvjldtbyxjiibdrltqiiighauai7hmvknwxhptsb4xat4qd.onion:38333
signet.addnode=f4kwoin7kk5a5kqpni7yqe25z66ckqu6bv37sqeluon24yne5rodzkqd.onion:38333
signet.addnode=nsgyo7begau4yecc46ljfecaykyzszcseapxmtu6adrfagfrrzrlngyd.onion:38333"|\
      sudo tee -a /mnt/hdd/${network}/${network}.conf
    fi
  fi

  removeParallelService
  if [ ${CHAIN} = mainnet ];then
    sudo cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service
  else 
    # /etc/systemd/system/${prefix}bitcoind.service
    echo "
[Unit]
Description=Bitcoin daemon on ${CHAIN}

[Service]
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/mnt/hdd/bitcoin/${prefix}bitcoind.pid
ExecStart=/usr/local/bin/bitcoind -${CHAIN} -daemon\
 -pid=/mnt/hdd/bitcoin/${prefix}bitcoind.pid
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${prefix}bitcoind.service
    fi
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}bitcoind
  echo "# OK - the bitcoin daemon on ${CHAIN} service is now enabled"

  # add aliases
  if [ ${CHAIN} != mainnet ];then
    if [ $(alias | grep -c ${prefix}bitcoin) -eq 0 ];then 
      bash -c "echo 'alias ${prefix}bitcoin-cli=\"/usr/local/bin/bitcoin-cli\
 -rpcport=${rpcprefix}8332\"' \
      >> /home/admin/_aliases.sh"
      bash -c "echo 'alias ${prefix}bitcoind=\"/usr/local/bin/bitcoind\
 -${CHAIN}\"' \
      >> /home/admin/_aliases.sh"
    fi
  fi

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the ${prefix}bitcoind.service is enabled, system is ready so starting service"
    sudo systemctl start ${prefix}bitcoind
  else
    echo "# OK - the ${prefix}bitcoindservice is enabled, to start manually use:"
    echo "sudo systemctl start ${prefix}bitcoind"
  fi

  isInstalled=$(systemctl status ${prefix}bitcoind | grep -c active)
  if [ $isInstalled -gt 0 ];then 
    echo "# Installed $(bitcoind --version | grep version)"
    echo 
    echo "# Monitor the ${prefix}bitcoind with:"
    if [ ${CHAIN} = signet ]; then
      echo "sudo tail -f /mnt/hdd/bitcoin/signet/debug.log"
    elif [ ${CHAIN} = testnet ]; then
      echo "sudo tail -f /mnt/hdd/bitcoin/testnet3/debug.log"
    elif [ ${CHAIN} = mainnet ]; then
      echo "sudo tail -f /mnt/hdd/bitcoin/debug.log"      
    fi
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu ${prefix}bitcoind"
    exit 1
  fi
}

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^${CHAIN}=" /mnt/hdd/raspiblitz.conf; then
  echo "${CHAIN}=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  installParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${CHAIN}=.*/${CHAIN}=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstall Bitcoin Core instance on ${CHAIN}"
  removeParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${CHAIN}=.*/${CHAIN}=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1