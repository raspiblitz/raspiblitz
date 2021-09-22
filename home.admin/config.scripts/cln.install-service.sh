#!/bin/bash

# help
if [ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "Script to set up or update the C-lightning systemd service"
  echo "Usage:"
  echo "/home/admin/config.scripts/cln.install-service.sh <mainnet|testnet|signet>"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cln <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

if [ $(sudo -u bitcoin cat ${CLNCONF} | grep -c "^sparko") -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cln-plugins-enabled/sparko ];then
    echo "# The Sparko plugin is not present but in config"
    /home/admin/config.scripts/cln-plugin.sparko.sh on $CHAIN
  fi
fi

if grep -Eq "${netprefix}clnEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
  if grep -Eq "${netprefix}clnAutoUnlock=on" /mnt/hdd/raspiblitz.conf;then
    passwordFile=/root/.${netprefix}cln.pw
  else
    passwordFile=/dev/shm/.${netprefix}cln.pw
  fi
  passwordInput="(cat $passwordFile;echo;cat $passwordFile) | "
  encryptedHSMoption="--encrypted-hsm"
else
  passwordInput=""
  encryptedHSMoption=""
fi

sudo systemctl stop ${netprefix}lightningd
sudo systemctl disable ${netprefix}lightningd
echo "# Create /etc/systemd/system/${netprefix}lightningd.service"
echo "
[Unit]
Description=c-lightning daemon on $CHAIN

[Service]
User=bitcoin
Group=bitcoin
Type=simple
ExecStart=/bin/sh -c '${passwordInput}/usr/local/bin/lightningd\
 --conf=${CLNCONF} ${encryptedHSMoption}'
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
" | sudo tee /etc/systemd/system/${netprefix}lightningd.service

sudo systemctl daemon-reload
sudo systemctl enable ${netprefix}lightningd
echo "# Enabled the ${netprefix}lightningd.service"

source /home/admin/raspiblitz.info
if [ "${state}" == "ready" ]; then
  sudo systemctl start ${netprefix}lightningd
  echo "# Started the ${netprefix}lightningd.service"
fi