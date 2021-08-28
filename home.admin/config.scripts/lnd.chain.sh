#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.chain.sh [on|off] [mainnet|testnet|signet]"
  echo
  exit 1
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ ${CHAIN} = testnet ]||[ ${CHAIN} = mainnet ];then
  echo "# Configuring the LND instance on ${CHAIN}"
elif [ ${CHAIN} = signet ]; then
  echo "# Signet is not yet supported in LND"
  echo "# see https://github.com/lightningnetwork/lnd/issues/5018"
  exit 1
else
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  netprefix="t"
  portprefix=1
  rpcportmod=1
  zmqprefix=21
elif [ ${CHAIN} = signet ];then
  netprefix="s"
  portprefix=3
  rpcportmod=3
  zmqprefix=23
elif [ ${CHAIN} = mainnet ];then
  netprefix=""
  portprefix=""
  rpcportmod=0
  zmqprefix=28
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${netprefix}bitcoind.service" ];then
    sudo -u bitcoin /usr/local/bin/lncli\
     --rpcserver localhost:1${rpcportmod}009 stop
    sudo systemctl stop ${netprefix}lnd
    sudo systemctl disable ${netprefix}lnd
    echo "# ${netprefix}lnd.service on ${CHAIN} is stopped and disabled"
    echo
  fi
}

source /home/admin/raspiblitz.info
# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}lnd=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}lnd=off" >> /mnt/hdd/raspiblitz.conf
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${CHAIN}" == "testnet" ] && [ "${testnet}" != "on" ]; then
    echo "# before activating testnet on lnd, first activate testnet on bitcoind"
    echo "err='missing bitcoin testnet'"
    exit 1
  fi

  if [ "${CHAIN}" == "signet" ] && [ "${signet}" != "on" ]; then
    echo "# before activating signet on lnd, first activate signet on bitcoind"
    echo "err='missing bitcoin signet'"
    exit 1
  fi

  sudo ufw allow ${portprefix}9735 comment '${netprefix}lnd'
  sudo ufw allow ${portprefix}8080 comment '${netprefix}lnd REST'
  sudo ufw allow 1${rpcportmod}009 comment '${netprefix}lnd RPC'

  echo "# Create /home/bitcoin/.lnd/${netprefix}lnd.conf"
  if [ ! -f /home/bitcoin/.lnd/${netprefix}lnd.conf ];then
    echo "# LND configuration

[Application Options]
# alias=ALIAS # up to 32 UTF-8 characters
# color=COLOR # choose from: https://www.color-hex.com/
listen=0.0.0.0:${portprefix}9735
rpclisten=0.0.0.0:1${rpcportmod}009
restlisten=0.0.0.0:${portprefix}8080
nat=false
debuglevel=debug
gc-canceled-invoices-on-startup=true 
gc-canceled-invoices-on-the-fly=true 
ignore-historical-gossip-filters=1 
sync-freelist=true
stagger-initial-reconnect=true
tlsautorefresh=1
tlsdisableautofill=1
tlscertpath=/home/bitcoin/.lnd/tls.cert
tlskeypath=/home/bitcoin/.lnd/tls.key

[Bitcoin]
bitcoin.active=1
bitcoin.${CHAIN}=1
bitcoin.node=bitcoind
" | sudo -u bitcoin tee /home/bitcoin/.lnd/${netprefix}lnd.conf
  else
    echo "# The file /home/bitcoin/.lnd/${netprefix}lnd.conf is already present"
  fi

  # systemd service  
  removeParallelService
  echo "# Create /etc/systemd/system/.lnd.service"
  echo "
[Unit]
Description=LND on $NETWORK

[Service]
User=bitcoin
Group=bitcoin
Type=simple
EnvironmentFile=/mnt/hdd/raspiblitz.conf
ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/lnd --configfile=/home/bitcoin/.lnd/${netprefix}lnd.conf
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
" | sudo tee /etc/systemd/system/${netprefix}lnd.service
  sudo systemctl enable ${netprefix}lnd 
  echo "# Enabled the ${netprefix}lnd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lnd
    echo "# Started the ${netprefix}lnd.service"
  fi

  echo
  echo "# Adding aliases"
  echo "\
alias ${netprefix}lncli=\"sudo -u bitcoin /usr/local/bin/lncli\
 -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009\"\
" | sudo tee -a /home/admin/_aliases

  echo
  echo "# The installed LND version is: $(sudo -u bitcoin /usr/local/bin/lnd --version)"
  echo   
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases"
  echo "# Monitor the ${netprefix}lnd with:"
  echo "sudo journalctl -fu ${netprefix}lnd"
  echo "sudo systemctl status ${netprefix}lnd"
  echo "# logs:"
  echo "sudo tail -f /home/bitcoin/.lnd/logs/bitcoin/${CHAIN}/lnd.log"
  echo "# for the command line options use"
  echo "${netprefix}lncli help"
  echo

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}lnd=.*/${netprefix}lnd=on/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  removeParallelService

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}lnd=.*/${netprefix}lnd=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1