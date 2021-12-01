#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "bitcoin.install.sh install - called by build.sdcard.sh"
  echo "Install or remove parallel chains for Bitcoin Core:"
  echo "bitcoin.install.sh [on|off] [signet|testnet|mainnet]"
  echo
  exit 1
fi

if [ "$1" = "install" ]; then
  echo "*** PREPARING BITCOIN ***"

  # set version (change if update is available)
  # https://bitcoincore.org/en/download/
  bitcoinVersion="22.0"
  
  # needed to check code signing
  # https://github.com/laanwj
  laanwjPGP="71A3 B167 3540 5025 D447 E8F2 7481 0B01 2346 C9A6"
  
  # prepare directories
  sudo rm -rf /home/admin/download
  sudo -u admin mkdir /home/admin/download
  cd /home/admin/download || exit 1

  # receive signer key
  if ! gpg --keyserver hkp://keyserver.ubuntu.com --recv-key "71A3 B167 3540 5025 D447 E8F2 7481 0B01 2346 C9A6"
  then
    echo "!!! FAIL !!! Couldn't download Wladimir J. van der Laan's PGP pubkey"
    exit 1
  fi
  
  # download signed binary sha256 hash sum file
  sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS
  
  # download signed binary sha256 hash sum file and check
  sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
  verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} | grep "${laanwjPGP}" -c)
  echo "correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  else
    echo
    echo "****************************************"
    echo "OK --> BITCOIN MANIFEST IS CORRECT"
    echo "****************************************"
    echo
  fi
  
  # bitcoinOSversion
  if [ "$(uname -m | grep -c 'arm')" -gt 1 ]; then
    bitcoinOSversion="arm-linux-gnueabihf"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 1 ]; then
    bitcoinOSversion="aarch64-linux-gnu"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 1 ]; then
    bitcoinOSversion="x86_64-linux-gnu"
  fi
  
  echo
  echo "*** BITCOIN CORE v${bitcoinVersion} for ${bitcoinOSversion} ***"

  # download resources
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  if [ ! -f "./${binaryName}" ]; then
     sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
  fi
  if [ ! -f "./${binaryName}" ]; then
     echo "!!! FAIL !!! Could not download the BITCOIN BINARY"
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
      echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
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
  installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
  if [ ${installed} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi
  echo "- Bitcoin install OK"
  exit 0
fi


# CHAIN is mainnet | testnet | signet
CHAIN=$2
if [ "${CHAIN}" != signet ]&&[ "${CHAIN}" != testnet ]&&[ "${CHAIN}" != mainnet ];then
  echo "# ${CHAIN} is not supported"
  exit 1
fi
# prefixes for parallel services
if [ ${CHAIN} = testnet ];then
  prefix="t"
  bitcoinprefix="test"
  zmqprefix=21  # zmqpubrawblock=21332 zmqpubrawtx=21333
  rpcprefix=1   # rpcport=18332
elif [ ${CHAIN} = signet ];then
  prefix="s"
  bitcoinprefix="signet"
  zmqprefix=23
  rpcprefix=3
elif [ ${CHAIN} = mainnet ];then
  prefix=""
  bitcoinprefix="main"
  zmqprefix=28
  rpcprefix=""
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
    sudo rm /etc/systemd/system/${prefix}bitcoind.service 2>/dev/null
    if [ ${bitcoinprefix} = signet ];then
      # check for signet service set up by joininbox  
      if [ -f "/etc/systemd/system/signetd.service" ];then
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
  # bitcoin.conf
  if [ ! -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    # add minimal config
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
    echo "
# bitcoind configuration for ${CHAIN}

# Connection settings
rpcuser=raspiblitz
rpcpassword=$randomRPCpass
${bitcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${bitcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333

onlynet=onion
proxy=127.0.0.1:9050

datadir=/mnt/hdd/bitcoin
" | sudo -u bitcoin tee /home/bitcoin/.bitcoin/bitcoin.conf
  else
    echo "# /home/bitcoin/.bitcoin/bitcoin.conf is present"
  fi
  
  # make sure rpcbind is correctly configured
  sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "rpcallowip" < /mnt/hdd/${network}/${network}.conf) -gt 0 ];then
    if [ $(grep -c "${bitcoinprefix}.rpcbind=" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
      echo "\
${bitcoinprefix}.rpcbind=127.0.0.1"|\
      sudo tee -a /mnt/hdd/${network}/${network}.conf
    fi
  fi

  # correct rpcport entry
  sudo sed -i s/^rpcport=/main.rpcport=/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "${bitcoinprefix}.rpcport" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
    echo "\
${bitcoinprefix}.rpcport=${rpcprefix}8332"|\
    sudo tee -a /mnt/hdd/${network}/${network}.conf
  fi

  # correct zmq entry
  sudo sed -i s/^zmqpubraw/main.zmqpubraw/g /mnt/hdd/${network}/${network}.conf
  if [ $(grep -c "${bitcoinprefix}.zmqpubrawblock" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
    echo "\
${bitcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${bitcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333"|\
    sudo tee -a /mnt/hdd/${network}/${network}.conf
  fi

  # addnode
  if [ ${bitcoinprefix} = signet ];then
    if [ $(grep -c "${bitcoinprefix}.addnode" < /mnt/hdd/${network}/${network}.conf) -eq 0 ];then
      echo "\
signet.addnode=s7fcvn5rblem7tiquhhr7acjdhu7wsawcph7ck44uxyd6sismumemcyd.onion:38333
signet.addnode=6megrst422lxzsqvshkqkg6z2zhunywhyrhy3ltezaeyfspfyjdzr3qd.onion:38333
signet.addnode=jahtu4veqnvjldtbyxjiibdrltqiiighauai7hmvknwxhptsb4xat4qd.onion:38333
signet.addnode=f4kwoin7kk5a5kqpni7yqe25z66ckqu6bv37sqeluon24yne5rodzkqd.onion:38333
signet.addnode=nsgyo7begau4yecc46ljfecaykyzszcseapxmtu6adrfagfrrzrlngyd.onion:38333"|\
      sudo tee -a /mnt/hdd/${network}/${network}.conf
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
ExecStart=/usr/local/bin/bitcoind -${CHAIN} -daemon -pid=/mnt/hdd/bitcoin/${prefix}bitcoind.pid -debuglogfile=/mnt/hdd/bitcoin/${prefix}debug.log
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
" | sudo tee /etc/systemd/system/${prefix}bitcoind.service
    fi
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}bitcoind
  echo "# OK - the bitcoin daemon on ${CHAIN} service is now enabled"

  echo "# Add aliases ${prefix}bitcoin-cli, ${prefix}bitcoind, ${prefix}bitcoinlog"
  if [ $(alias | grep -c "alias ${prefix}bitcoin-cli") -eq 0 ];then 
    echo "\
alias ${prefix}bitcoin-cli=\"/usr/local/bin/bitcoin-cli\
 -rpcport=${rpcprefix}8332\"
alias ${prefix}bitcoind=\"/usr/local/bin/bitcoind -${CHAIN}\"\
"  | sudo tee -a /home/admin/_aliases
  fi
  if [ $(alias | grep -c "alias ${prefix}bitcoinlog") -eq 0 ];then 
    if [ ${CHAIN} = signet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/signet/debug.log"
    elif [ ${CHAIN} = testnet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/testnet3/debug.log"
    elif [ ${CHAIN} = mainnet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/debug.log"      
    fi
    echo "\
alias ${prefix}bitcoinlog=\"sudo tail -n 30 -f ${bitcoinlogpath}\"\
"  | sudo tee -a /home/admin/_aliases
  fi
  sudo chown admin:admin /home/admin/_aliases

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
    echo "# Installed $(bitcoind --version | grep version)"
    echo 
    echo "# Monitor the ${prefix}bitcoind with:"
    echo "# sudo tail -f /mnt/hdd/bitcoin/${prefix}debug.log"
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu ${prefix}bitcoind"
    exit 1
  fi
}

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^${CHAIN}=" /mnt/hdd/raspiblitz.conf; then
  NEWENTRY="${CHAIN}=off"
  sudo /bin/sh -c "echo '$NEWENTRY' >> /mnt/hdd/raspiblitz.conf" 
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
  echo "# Uninstall Bitcoin Core instance on ${CHAIN}"
  removeParallelService
  # setting value in raspi blitz config
  sudo sed -i "s/^${CHAIN}=.*/${CHAIN}=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1