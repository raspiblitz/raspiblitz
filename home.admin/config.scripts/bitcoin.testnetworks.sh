#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo "Install a parallel testnet or signet service"
  echo "bitcoin.testnetwork.sh [on|off] [signet|testnet]"
  exit 1
fi

parallelService=$2
if [ $parallelService = signet ] || [ $parallelService = testnet ];then
  echo "# Installing $parallelService"
else
  echo "# $parallelService not supported"
  exit 1
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${parallelService}d.service" ];then
    sudo systemctl stop ${parallelService}d
    sudo systemctl disable ${parallelService}d
    echo "# Bitcoin Core on ${parallelService} service is stopped and disabled"
    echo
  fi
}

function installParallelService() {
  # ${parallelService}.conf
  if [ ! -f /home/bitcoin/.bitcoin/${parallelService}.conf ];then
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for ${parallelService}

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/${parallelService}.conf
  else
    echo "# /home/bitcoin/.bitcoin/${parallelService}.conf is present"
  fi

  removeParallelService
  # /etc/systemd/system/${parallelService}d.service
  echo "
[Unit]
Description=Bitcoin daemon on ${parallelService}

[Service]
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/mnt/hdd/bitcoin/${parallelService}d.pid
ExecStart=/usr/local/bin/bitcoind -${parallelService} -daemon \
 -conf=/home/bitcoin/.bitcoin/${parallelService}.conf \
 -pid=/mnt/hdd/bitcoin/${parallelService}d.pid
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${parallelService}d.service
  sudo systemctl enable ${parallelService}d
  echo "# OK - the bitcoin daemon on ${parallelService} service is now enabled"

  # add aliases
  if [ $(alias | grep -c ${parallelService}) -eq 0 ];then 
    bash -c "echo 'alias ${parallelService}-cli=\"/usr/local/bin/bitcoin-cli\
 -${parallelService}\
 -conf=/home/bitcoin/.bitcoin/${parallelService}.conf\"' \
    >> /home/admin/_aliases.sh"
    bash -c "echo 'alias ${parallelService}d=\"/usr/local/bin/bitcoind\
 -${parallelService}\
 -conf=/home/bitcoin/.bitcoin/${parallelService}.conf\"' \
    >> /home/admin/_aliases.sh"
  fi

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the ${parallelService}d.service is enabled, system is ready so starting service"
    sudo systemctl start ${parallelService}d
  else
    echo "# OK - the ${parallelService}dservice is enabled, to start manually use: 'sudo systemctl start ${parallelService}d'"
  fi

  isInstalled=$(systemctl status ${parallelService}d | grep -c active)
  if [ $isInstalled -gt 0 ];then 
    echo "# Installed $(bitcoind --version | grep version) ${parallelService}d.service"
    echo 
    echo "# Monitor the ${parallelService} bitcoind with:"
    if [ ${parallelService} = signet ]; then
      echo "# 'sudo tail -f /mnt/hdd/bitcoin/signet/debug.log'"
    elif [ ${parallelService} = testnet ]; then
      echo "# 'sudo tail -f /mnt/hdd/bitcoin/testnet3/debug.log'"
    fi
    echo
  else
    echo "# Installation failed"
    exit 1
  fi
}

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^${parallelService}=" /mnt/hdd/raspiblitz.conf; then
  echo "${parallelService}=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  installParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${parallelService}=.*/${parallelService}=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

# switch off
if [ "$1" = "0sudo " ] || [ "$1" = "off" ]; then
  removeParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${parallelService}=.*/${parallelService}=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1