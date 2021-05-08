#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo "Install a parallel signet service"
  echo "bitcoin.signet.sh [on|off]"
  exit 1
fi

function removeSignetdService() {
  if [ -f "/etc/systemd/system/signetd.service" ];then
    sudo systemctl stop signetd
    sudo systemctl disable signetd
    echo "# Bitcoin Core on signet service is stopped and disabled"
    echo
  fi
}

function installSignet() {
  # signet.conf
  if [ ! -f /home/bitcoin/.bitcoin/signet.conf ];then
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for signet

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/signet.conf
  else
    echo "# /home/bitcoin/.bitcoin/signet.conf is present"
  fi

  removeSignetdService
  # /etc/systemd/system/signetd.service
  echo "
[Unit]
Description=Bitcoin daemon on signet

[Service]
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/mnt/hdd/bitcoin//signetd.pid
ExecStart=/usr/local/bin/bitcoind -signet -daemon \
 -conf=/home/bitcoin/.bitcoin/signet.conf \
 -pid=/mnt/hdd/bitcoin/signetd.pid
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/signetd.service
  sudo systemctl enable signetd
  echo "# OK - the bitcoin daemon on signet service is now enabled"

  # add aliases
  if [ $(alias | grep -c signet) -eq 0 ];then 
    bash -c "echo 'alias signet-cli=\"/usr/local/bin/bitcoin-cli -signet\"' >> /home/admin/_aliases.sh"
    bash -c "echo 'alias signetd=\"/usr/local/bin/bitcoind -signet\"' >> /home/admin/_aliases.sh"
  fi

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the signetd.service is enabled, system is ready so starting service"
    sudo systemctl start signetd
  else
    echo "# OK - the signetdservice is enabled, to start manually use: 'sudo systemctl start signetd'"
  fi

  isInstalled=$(systemctl status signetd | grep -c active)
  if [ $isInstalled -gt 0 ];then 
    echo "# Installed $(bitcoind --version | grep version) signetd.service"
    echo 
    echo "# Monitor the signet bitcoind with:"
    echo "# 'sudo tail -f /mnt/hdd/bitcoin/signet/debug.log'"
    echo
  else
    echo "# Installation failed"
    exit 1
  fi
}

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^signet=" /mnt/hdd/raspiblitz.conf; then
  echo "signet=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  installSignet
  # setting value in raspi blitz config
  sudo sed -i "s/^signet=.*/signet=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  removeSignetdService
  # setting value in raspi blitz config
  sudo sed -i "s/^signet=.*/signet=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1