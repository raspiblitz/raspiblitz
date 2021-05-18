#!/bin/bash

CLRESTVERSION="v0.4.4"

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning-REST install script"
  echo "the default version is: $CLRESTVERSION"
  echo "setting up on ${chain}net unless otherwise specified"
  echo "mainnet / signet / testnet instances cannot run parallel"
  echo
  echo "usage:"
  echo "bonus.clnrest.sh on  <signet|testnet>"
  echo "bonus.clnrest.sh off"
  echo
  exit 1
fi

# bitcoin mainnet / signet / testnet
if [ "$1" = on ] || [ "$1" = off ] && [ $# -gt 1 ];then
  if [ $2 = main ]||[ $2 = mainnet ]||[ $2 = bitcoin ];then
    NETWORK=bitcoin
  else
    NETWORK=$2
  fi
else 
  if [ $chain = main ];then
    NETWORK=bitcoin
  else
    NETWORK=${chain}net
  fi
fi

# prefix for parallel testnetwork services
if [ $NETWORK = testnet ];then
  prefix="t"
  portprefix=1
elif [ $NETWORK = signet ];then
  prefix="s"
  portprefix=3
elif [ $NETWORK = bitcoin ];then
  prefix=""
  portprefix=""
else
  echo "$NETWORK is not supported"
  exit 1
fi

echo "# Running 'bonus.clnrest.sh $*'"

if [ $1 = on ];then
  echo "# Setting up c-lightning-REST for $NETWORK"

  cd /home/bitcoin || exit 1
  sudo -u bitcoin git clone https://github.com/saubyk/c-lightning-REST
  cd c-lightning-REST || exit 1
  sudo -u bitcoin git reset --hard $CLRESTVERSION
  sudo -u bitcoin npm install
  sudo -u bitcoin cp sample-cl-rest-config.json cl-rest-config.json
  sudo -u bitcoin sed -i "s/3001/${portprefix}6100/g" cl-rest-config.json

  # symlink to /home/bitcoin/.lightning/lightning-rpc from the chosen network directory
  sudo rm /home/bitcoin/.lightning/lightning-rpc # delete old symlink
  sudo ln -s /home/bitcoin/.lightning/${NETWORK}/lightning-rpc /home/bitcoin/.lightning/
  
  echo "
# systemd unit for c-lightning-REST for ${NETWORK}
#/etc/systemd/system/clnrest.service
[Unit]
Description=c-lightning-REST daemon for $NETWORK
Wants=${prefix}lightningd.service
After=${prefix}lightningd.service

[Service]
ExecStart=/usr/bin/node /home/bitcoin/c-lightning-REST/cl-rest.js
User=bitcoin
Restart=always
TimeoutSec=120
RestartSec=30

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/clnrest.service

  sudo systemctl enable clnrest
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the clnrest.service is enabled, system is ready so starting service"
    sudo systemctl start clnrest
  else
    echo "# OK - the clnrest.service is enabled, to start manually use: 'sudo systemctl start clnrest'"
  fi
  echo
  echo "# Monitor with:"
  echo "sudo journalctl -f -u clnrest"
  echo
fi

if [ $1 = off ];then
  echo "# Removing c-lightning-REST for $NETWORK"
  sudo systemctl stop clnrest
  sudo systemctl disable clnrest
  sudo rm -rf /home/bitcoin/c-lightning-REST
fi
