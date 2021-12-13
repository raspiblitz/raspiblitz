#!/bin/bash

# help
if [ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "Script to set up or update the C-lightning systemd service"
  echo "Usage:"
  echo "/home/admin/config.scripts/cl.install-service.sh <mainnet|testnet|signet>"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

if [ $(sudo -u bitcoin cat ${CLCONF} | grep -c "^sparko") -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/sparko ];then
    echo "# The Sparko plugin is not present but in config"
    /home/admin/config.scripts/cl-plugin.sparko.sh on $CHAIN norestart
  fi
fi

if [ $(sudo -u bitcoin cat ${CLCONF} | grep -c "^http-pass") -gt 0 ];then
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ]; then
    echo "# The clHTTPplugin is not present but in config"
    /home/admin/config.scripts/cl-plugin.http.sh on norestart
  fi
fi

if [ $(sudo -u bitcoin cat ${CLCONF} | grep -c "^feeadjuster") -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ];then
    echo "# The feeadjuster plugin is not present but in config"
    /home/admin/config.scripts/cl-plugin.feeadjuster.sh on $CHAIN norestart
  fi
fi

if grep -Eq "${netprefix}clEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
  if grep -Eq "${netprefix}clAutoUnlock=on" /mnt/hdd/raspiblitz.conf;then
    passwordFile=/root/.${netprefix}cl.pw
  else
    passwordFile=/dev/shm/.${netprefix}cl.pw
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
ExecStartPre=-/home/admin/config.scripts/cl.check.sh prestart $CHAIN
ExecStart=/bin/sh -c '${passwordInput}/usr/local/bin/lightningd\
 --conf=${CLCONF} ${encryptedHSMoption}'
User=bitcoin
Group=bitcoin
Type=simple
Restart=always
TimeoutSec=240
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
