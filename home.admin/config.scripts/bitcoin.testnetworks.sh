#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo "Install a parallel testnet or signet service"
  echo "bitcoin.testnetwork.sh [on|off] [signet|testnet]"
  exit 1
fi

testnetwork=$2
if [ ${testnetwork} = signet ] || [ ${testnetwork} = testnet ];then
  echo "# Installing Bitcoin Core instance on ${testnetwork}"
else
  echo "# ${testnetwork} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${testnetwork} = testnet ];then
  prefix="t"
  portprefix=1
elif [ ${testnetwork} = signet ];then
  prefix="s"
  portprefix=3
fi 

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}bitcoind.service" ];then
    sudo systemctl stop ${prefix}bitcoind
    sudo systemctl disable ${prefix}bitcoind
    echo "# Bitcoin Core on ${testnetwork} service is stopped and disabled"
    echo
  fi
}

function installParallelService() {
  # bitcoin.conf
  if [ ! -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for ${testnetwork}

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/bitcoin.conf
  else
    echo "# /home/bitcoin/.bitcoin/bitcoin.conf is present"
  fi

  removeParallelService
  # /etc/systemd/system/${prefix}bitcoind.service
  echo "
[Unit]
Description=Bitcoin daemon on ${testnetwork}

[Service]
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/mnt/hdd/bitcoin/${prefix}bitcoind.pid
ExecStart=/usr/local/bin/bitcoind -${testnetwork} -daemon\
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
  sudo systemctl enable ${prefix}bitcoind
  echo "# OK - the bitcoin daemon on ${testnetwork} service is now enabled"

  # add aliases
  if [ $(alias | grep -c ${prefix}bitcoin) -eq 0 ];then 
    bash -c "echo 'alias ${prefix}bitcoin-cli=\"/usr/local/bin/bitcoin-cli\
 -${testnetwork}\"' \
    >> /home/admin/_aliases.sh"
    bash -c "echo 'alias ${prefix}bitcoind=\"/usr/local/bin/bitcoind\
 -${testnetwork}\"' \
    >> /home/admin/_aliases.sh"
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
    if [ ${testnetwork} = signet ]; then
      echo "sudo tail -f /mnt/hdd/bitcoin/signet/debug.log"
    elif [ ${testnetwork} = testnet ]; then
      echo "sudo tail -f /mnt/hdd/bitcoin/testnet3/debug.log"
    fi
    echo
  else
    echo "# Installation failed"
    exit 1
  fi
}

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^${testnetwork}=" /mnt/hdd/raspiblitz.conf; then
  echo "${testnetwork}=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  installParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${testnetwork}=.*/${testnetwork}=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

# switch off
if [ "$1" = "0sudo " ] || [ "$1" = "off" ]; then
  removeParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${testnetwork}=.*/${testnetwork}=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1