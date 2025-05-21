#!/bin/bash

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="29.0"


# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "bitcoin.install.sh install - called by build.sdcard.sh"
  echo "Install or remove parallel chains for Bitcoin Core:"
  echo "bitcoin.install.sh install"
  echo "bitcoin.install.sh [on|off] [signet|testnet|mainnet]"
  echo "Installs Bitcoin Core $bitcoinVersion by default"
  echo
  exit 1
fi

echo "# Running: bitcoin.install.sh $*"

# mainnet | testnet | signet
CHAIN=${2:-mainnet}
if [ "${CHAIN}" != signet ] && [ "${CHAIN}" != testnet ] && [ "${CHAIN}" != mainnet ]; then
  echo "# ${CHAIN} is not supported"
  exit 1
fi
# prefixes for parallel services
if [ "${CHAIN}" = testnet ]; then
  prefix="t"
  bitcoinprefix="test"
  zmqprefix=21 # zmqpubrawblock=21332 zmqpubrawtx=21333 zmqpubhashblock=21334
  rpcprefix=1  # rpcport=18332
elif [ ${CHAIN} = signet ]; then
  prefix="s"
  bitcoinprefix="signet"
  zmqprefix=23
  rpcprefix=3
elif [ ${CHAIN} = mainnet ]; then
  prefix=""
  bitcoinprefix="main"
  zmqprefix=28
  rpcprefix=""
fi
# bitcoinlogpath
if [ ${CHAIN} = signet ]; then
  bitcoinlogpath="/mnt/hdd/app-storage/bitcoin/signet/debug.log"
elif [ ${CHAIN} = testnet ]; then
  bitcoinlogpath="/mnt/hdd/app-storage/bitcoin/testnet3/debug.log"
elif [ ${CHAIN} = mainnet ]; then
  bitcoinlogpath="/mnt/hdd/app-storage/bitcoin/debug.log"
fi

function addBitcoinAliases {
  echo "# Add aliases ${prefix}bitcoin-cli, ${prefix}bitcoinlog"
  sudo -u admin touch /home/admin/_aliases
  if ! grep "alias ${prefix}bitcoin-cli" /home/admin/_aliases; then
    echo "alias ${prefix}bitcoin-cli=\"sudo -u bitcoin /usr/local/bin/bitcoin-cli -rpcport=${rpcprefix}8332\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias ${prefix}bitcoinlog" /home/admin/_aliases; then
    echo "alias ${prefix}bitcoinlog=\"sudo -u bitcoin tail -n 30 -f ${bitcoinlogpath}\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias bitcoinconf" /home/admin/_aliases; then
    echo "alias bitcoinconf=\"sudo nano /mnt/hdd/app-data/bitcoin/bitcoin.conf\"" |
      sudo tee -a /home/admin/_aliases
  fi
  sudo chown admin:admin /home/admin/_aliases
}

if [ "$1" = "install" ]; then
  echo "*** PREPARING BITCOIN ***"

  # prepare directories
  sudo rm -rf /home/admin/download
  sudo -u admin mkdir /home/admin/download
  cd /home/admin/download || exit 1

  echo "# Receive signer keys"
  curl -s "https://api.github.com/repos/bitcoin-core/guix.sigs/contents/builder-keys" |
    jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done

  # download signed binary sha256 hash sum file
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS
  # download the signed binary sha256 hash sum file and check
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS.asc https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc

  if gpg --verify SHA256SUMS.asc; then
    echo
    echo "****************************************"
    echo "OK --> BITCOIN MANIFEST IS CORRECT"
    echo "****************************************"
    echo
  else
    echo
    echo "# BUILD FAILED --> the PGP verification failed"
    exit 1
  fi

  # bitcoinOSversion
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    bitcoinOSversion="arm-linux-gnueabihf"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    bitcoinOSversion="aarch64-linux-gnu"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    bitcoinOSversion="x86_64-linux-gnu"
  fi

  echo
  echo "*** BITCOIN CORE v${bitcoinVersion} for ${bitcoinOSversion} ***"

  # download resources
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  if [ ! -f "./${binaryName}" ]; then
    echo "# Downloading https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName} ..."
    sudo -u admin wget --quiet https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
  fi
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Could not download the BITCOIN BINARY"
    exit 1
  else

    # check binary checksum test
    echo "- checksum test"
    # get the sha256 value for the corresponding platform from signed hash sum file
    bitcoinSHA256=$(grep -i "${binaryName}" SHA256SUMS | cut -d " " -f1)
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    echo "Valid SHA256 checksum should be: ${bitcoinSHA256}"
    echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
    if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
      echo "# FAIL # Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
      rm -v ./${binaryName}
      exit 1
    else
      echo
      echo "********************************************"
      echo "OK --> VERIFIED BITCOIN CORE BINARY CHECKSUM"
      echo "********************************************"
      echo
      sleep 10
      echo
    fi
  fi

  # install
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
  sleep 3
  if ! sudo /usr/local/bin/bitcoind --version | grep "${bitcoinVersion}"; then
    echo
    echo "# BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi

  addBitcoinAliases

  echo "- Bitcoin install OK"
  exit 0
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}bitcoind.service" ]; then
    if [ ${CHAIN} != mainnet ]; then
      /usr/local/bin/bitcoin-cli -${CHAIN} stop
    else
      /usr/local/bin/bitcoin-cli stop
    fi
    sudo systemctl stop ${prefix}bitcoind
    sudo systemctl disable ${prefix}bitcoind
    sudo rm /etc/systemd/system/${prefix}bitcoind.service 2>/dev/null
    if [ ${bitcoinprefix} = signet ]; then
      # check for signet service set up by joininbox
      if [ -f "/etc/systemd/system/signetd.service" ]; then
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

  # make sure rpcbind is correctly configured
  sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/app-data/bitcoin/bitcoin.conf
  if grep "rpcallowip" /mnt/hdd/app-data/bitcoin/bitcoin.conf; then
    if ! grep "${bitcoinprefix}.rpcbind=" /mnt/hdd/app-data/bitcoin/bitcoin.conf; then
      echo "${bitcoinprefix}.rpcbind=127.0.0.1" |
        sudo tee -a /mnt/hdd/app-data/bitcoin/bitcoin.conf
    fi
  fi

  # correct rpcport entry
  sudo sed -i s/^rpcport=/main.rpcport=/g /mnt/hdd/app-data/bitcoin/bitcoin.conf
  if ! grep "${bitcoinprefix}.rpcport" /mnt/hdd/app-data/bitcoin/bitcoin.conf; then
    echo "${bitcoinprefix}.rpcport=${rpcprefix}8332" |
      sudo tee -a /mnt/hdd/app-data/bitcoin/bitcoin.conf
  fi

  # correct zmq entry
  sudo sed -i s/^zmqpubraw/main.zmqpubraw/g /mnt/hdd/app-data/bitcoin/bitcoin.conf
  if ! grep "${bitcoinprefix}.zmqpubrawblock" /mnt/hdd/app-data/bitcoin/bitcoin.conf; then
    echo "\
${bitcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${bitcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333" |
      sudo tee -a /mnt/hdd/app-data/bitcoin/bitcoin.conf
  fi

  # addnode
  if [ ${bitcoinprefix} = signet ]; then
    if [ $(grep -c "${bitcoinprefix}.addnode" </mnt/hdd/app-data/bitcoin/bitcoin.conf) -eq 0 ]; then
      echo "\
signet.addnode=s7fcvn5rblem7tiquhhr7acjdhu7wsawcph7ck44uxyd6sismumemcyd.onion:38333
signet.addnode=6megrst422lxzsqvshkqkg6z2zhunywhyrhy3ltezaeyfspfyjdzr3qd.onion:38333
signet.addnode=jahtu4veqnvjldtbyxjiibdrltqiiighauai7hmvknwxhptsb4xat4qd.onion:38333
signet.addnode=f4kwoin7kk5a5kqpni7yqe25z66ckqu6bv37sqeluon24yne5rodzkqd.onion:38333
signet.addnode=nsgyo7begau4yecc46ljfecaykyzszcseapxmtu6adrfagfrrzrlngyd.onion:38333" |
        sudo tee -a /mnt/hdd/app-data/bitcoin/bitcoin.conf
    fi
  fi

  removeParallelService

  # /etc/systemd/system/${prefix}bitcoind.service
  # based on https://github.com/bitcoin/bitcoin/blob/master/contrib/init/bitcoind.service
  chainparameter=""
  if [ "${CHAIN}" != "mainnet" ]; then
    chainparameter="-${CHAIN}"
  fi
  echo "
[Unit]
Description=Bitcoin daemon on ${CHAIN}

Wants=redis.service
After=redis.service

[Service]
Environment='MALLOC_ARENA_MAX=1'
ExecStartPre=-/home/admin/config.scripts/bitcoin.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/bitcoind ${chainparameter} \\
                                  -daemonwait \\
                                  -conf=/mnt/hdd/app-data/bitcoin/bitcoin.conf \\
                                  -datadir=/mnt/hdd/app-storage/bitcoin
PermissionsStartOnly=true

# Process management
####################
Type=forking
Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Directory creation and permissions
####################################
# Run as bitcoin:bitcoin
User=bitcoin
Group=bitcoin

StandardOutput=null
StandardError=journal

# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Deny access to /home, /root and /run/user
ProtectHome=true
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
" | sudo tee /etc/systemd/system/${prefix}bitcoind.service
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}bitcoind
  echo "# OK - the bitcoin daemon on ${CHAIN} service is now enabled"

  addBitcoinAliases

  source <(/home/admin/_cache.sh get state)

  if [ "${state}" == "ready" ]; then
    echo "# OK - the ${prefix}bitcoind.service is enabled, system is ready so starting service"
    sudo systemctl start ${prefix}bitcoind
  else
    echo "# OK - the ${prefix}bitcoindservice is enabled, to start manually use:"
    echo "sudo systemctl start ${prefix}bitcoind"
  fi

  isInstalled=$(systemctl status ${prefix}bitcoind | grep -c active)
  if [ $isInstalled -gt 0 ]; then
    echo "# Installed $(sudo -u bitcoin bitcoind --version | grep version)"
    echo
    echo "# Monitor the ${prefix}bitcoind with:"
    echo "# sudo tail -f /mnt/hdd/app-storage/bitcoin/${prefix}debug.log"
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu ${prefix}bitcoind"
    exit 1
  fi
}

source /mnt/hdd/app-data/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # make sure the bitcoin directory is present and is linked
  echo "# Bitcoin datadir"
  source <(sudo /home/admin/config.scripts/blitz.data.sh status)
  mkdir -p ${storageMountedPath}/app-storage/bitcoin
  echo "# Liniking /bitcoin"
  unlink /mnt/hdd/bitcoin 2>/dev/null
  ln -s ${storageMountedPath}/app-storage/bitcoin /mnt/hdd/bitcoin
  chown -R bitcoin:bitcoin /mnt/hdd/bitcoin
  chmod -R 777 /mnt/hdd/bitcoin

  installParallelService
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CHAIN} "on"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstall Bitcoin Core instance on ${CHAIN}"
  removeParallelService
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CHAIN} "off"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
