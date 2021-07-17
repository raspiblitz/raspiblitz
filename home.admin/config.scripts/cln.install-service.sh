#!/bin/bash

# script to set up or update the CLN systemd service
# usage:
# /home/admin/config.scripts/cln.install-service.sh $CHAIN

source /mnt/hdd/raspiblitz.conf
source /home/admin/raspiblitz.info

# source <(/home/admin/config.scripts/network.aliases.sh getvars cln <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

if [ $(grep -c "^sparko" < /home/bitcoin/.lightning/${netprefix}config) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cln-plugins-enabled/sparko ];then
    echo "# The Sparko plugin is not present despite being configured"
    /home/admin/config.scripts/cln-plugin.sparko.sh on $CHAIN
  fi
  sparkoStart="--plugin=/home/bitcoin/${netprefix}cln-plugins-enabled/sparko"
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
 --conf=/home/bitcoin/.lightning/${netprefix}config\
 ${sparkoStart} ${encryptedHSMoption}'
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
if [ "${state}" == "ready" ]; then
  sudo systemctl start ${netprefix}lightningd
  echo "# Started the ${netprefix}lightningd.service"
fi