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
    passwordFile=/home/bitcoin/.${netprefix}cl.pw
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
# based on https://github.com/ElementsProject/lightning/blob/master/contrib/init/lightningd.service
echo "# Create /etc/systemd/system/${netprefix}lightningd.service"
echo "
[Unit]
Description=c-lightning daemon on $CHAIN
Requires=${netprefix}bitcoind.service
After=${netprefix}bitcoind.service
Wants=network-online.target
After=network-online.target

[Service]
ExecStartPre=-/home/admin/config.scripts/cl.check.sh prestart $CHAIN
ExecStart=/bin/sh -c '${passwordInput}/usr/local/bin/lightningd \\
                       --conf=${CLCONF} ${encryptedHSMoption} \\
                       --pid-file=/run/lightningd/${netprefix}lightningd.pid'

# Creates /run/lightningd owned by bitcoin
RuntimeDirectory=lightningd

User=bitcoin
Group=bitcoin
# Type=forking hangs on restart
Type=simple
PIDFile=/run/lightningd/${netprefix}lightningd.pid
Restart=on-failure

TimeoutSec=240
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${netprefix}lightningd.service

sudo systemctl daemon-reload
sudo systemctl enable ${netprefix}lightningd
echo "# Enabled the ${netprefix}lightningd.service"

source <(/home/admin/_cache.sh get state)
if [ "${state}" == "ready" ]; then
  sudo systemctl start ${netprefix}lightningd
  echo "# Started the ${netprefix}lightningd.service"
fi
