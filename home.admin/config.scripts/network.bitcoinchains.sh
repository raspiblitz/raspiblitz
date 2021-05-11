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
if [ ${CHAIN} = signet ]||[ ${CHAIN} = testnet ]||[ ${CHAIN} = mainnet ];then
  echo "# Installing Bitcoin Core instance on ${CHAIN}"
else
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  prefix="t"
  portprefix=1
elif [ ${CHAIN} = signet ];then
  prefix="s"
  portprefix=3
elif [ ${CHAIN} = mainnet ];then
  prefix=""
  portprefix=""
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
    echo "# Bitcoin Core on ${CHAIN} service is stopped and disabled"
    echo
  fi
}

function installParallelService() {
  # bitcoin.conf
  if [ ! -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for ${CHAIN}

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/bitcoin.conf
  else
    echo "# /home/bitcoin/.bitcoin/bitcoin.conf is present"
    # make sure rpcbind is correctly configured
    bindIP=$(grep -c "^rpcbind=" <  /mnt/hdd/${network}/${network}.conf)
    if [ $bindIP -gt 0 ];then
      sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/${network}/${network}.conf
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
 -pid=/mnt/hdd/bitcoin/${prefix}bitcoind.pid\
 -zmqpubrawblock=tcp://127.0.0.1:${portprefix}8332\
 -zmqpubrawtx=tcp://127.0.0.1:${portprefix}8333
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

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
 -${CHAIN}\"' \
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
    echo "# Installed $(bitcoind --version | grep version) ${prefix}bitcoind.service"
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
  removeParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${CHAIN}=.*/${CHAIN}=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1