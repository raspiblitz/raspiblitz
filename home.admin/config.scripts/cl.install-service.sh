#!/bin/bash

# help
if [ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "Script to set up or update the Core Lightning systemd service"
  echo "Usage:"
  echo "/home/admin/config.scripts/cl.install-service.sh <mainnet|testnet|signet>"
  echo
  exit 1
fi

lightningdBin="/usr/local/bin/lightningd"

# The lightningd option to read the hsm_secret password from stdin:
# --hsm-passphrase since CLN v25.12, where --encrypted-hsm is deprecated
# (refused with allow-deprecated-apis=false and once the deprecation ends);
# --encrypted-hsm for older versions.
# Uses 'lightningd --version': it is handled before the config is read,
# unlike '--help' which needs a full start (config, log file, plugins).
function hsmPassphraseOption() {
  local version
  version=$("${lightningdBin}" --version 2>/dev/null | head -n 1 |
    sed -nE 's/^v?([0-9]+\.[0-9]+(\.[0-9]+)?).*$/\1/p')
  if [ -n "${version}" ] &&
   [ "$(printf '%s\n' "${version}" "25.12" | sort -V | head -n 1)" != "25.12" ]; then
    echo "--encrypted-hsm"
  else
    echo "--hsm-passphrase"
  fi
}

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

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

if grep -Eq "${netprefix}clEncryptedHSM=on" /mnt/hdd/app-data/raspiblitz.conf;then
  if grep -Eq "${netprefix}clAutoUnlock=on" /mnt/hdd/app-data/raspiblitz.conf;then
    passwordFile=/home/bitcoin/.${netprefix}cl.pw
  else
    passwordFile=/dev/shm/.${netprefix}cl.pw
  fi
  passwordInput="(cat $passwordFile;echo;cat $passwordFile) | "
  encryptedHSMoption="$(hsmPassphraseOption)"
else
  passwordInput=""
  encryptedHSMoption=""
fi

sudo mkdir -p /run/lightningd
sudo chown bitcoin:bitcoin /run/lightningd

sudo systemctl stop ${netprefix}lightningd
sudo systemctl disable ${netprefix}lightningd
# based on https://github.com/ElementsProject/lightning/blob/master/contrib/init/lightningd.service
echo "# Create /etc/systemd/system/${netprefix}lightningd.service"
echo "
[Unit]
Description=c-lightning daemon on $CHAIN
Requires=${netprefix}bitcoind.service
After=${netprefix}bitcoind.service
PartOf=${netprefix}bitcoind.service
Wants=network-online.target
After=network-online.target

[Service]
ExecStartPre=-/home/admin/config.scripts/cl.check.sh prestart $CHAIN
ExecStart=/bin/sh -c '${passwordInput}${lightningdBin} --conf=${CLCONF} ${encryptedHSMoption} --rpc-file-mode 0660'
ExecStartPost=-/home/admin/config.scripts/cl.check.sh poststart $CHAIN

# Creates /run/lightningd owned by bitcoin
RuntimeDirectory=lightningd
User=bitcoin
Group=bitcoin
# Use Type=simple - most reliable for CLN
Type=simple
# Don't use PIDFile with Type=simple to avoid conflicts
Restart=always
RestartSec=60
TimeoutSec=240
# Increase startup timeout for CLN to fully initialize
TimeoutStartSec=300
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
