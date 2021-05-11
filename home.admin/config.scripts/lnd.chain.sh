#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.chains.sh [on|off] [signet|testnet|mainnet]"
  echo
  exit 1
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ ${CHAIN} = testnet ]||[ ${CHAIN} = mainnet ];then
  echo "# Installing the LND instance on ${CHAIN}"
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
  prefix="t"
  portprefix=1
  zmqprefix=21
elif [ ${CHAIN} = signet ];then
  prefix="s"
  portprefix=3
  zmqprefix=23
elif [ ${CHAIN} = mainnet ];then
  prefix=""
  portprefix=""
  zmqprefix=28
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}bitcoind.service" ];then
    sudo -u bitcoin /usr/local/bin/lncli\
     --rpcserver localhost:1${portprefix}009 stop
    sudo systemctl stop ${prefix}lnd
    sudo systemctl disable ${prefix}lnd
    echo "# ${prefix}lnd.service on ${CHAIN} is stopped and disabled"
    echo
  fi
}

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# Create /home/bitcoin/.lnd/${prefix}lnd.conf"
  if [ ! -f /home/bitcoin/.lnd/${prefix}lnd.conf ];then
  RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
  RPCPSW=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    echo "
# LND configuration
bitcoin.${CHAIN}=1

[Application Options]
# alias=ALIAS # up to 32 UTF-8 characters
# color=COLOR # choose from: https://www.color-hex.com/
listen=0.0.0.0:${portprefix}9735
rpclisten=0.0.0.0:1${portprefix}009
restlisten=0.0.0.0:${portprefix}8080
accept-keysend=true
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
bitcoin.node=bitcoind

[bitcoind]
bitcoind.rpcuser=$RPCUSER
bitcoind.rpcpass=$RPCPSW
bitcoind.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
bitcoind.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333

[Watchtower]
watchtower.active=1
watchtower.listen=0.0.0.0:${portprefix}9111

[Wtclient]
wtclient.active=1

[Tor]
tor.active=true
tor.streamisolation=true
tor.v3=true
" | sudo -u bitcoin tee /home/bitcoin/.lnd/${prefix}lnd.conf
  else
    echo "# The file /home/bitcoin/.lnd/${prefix}lnd.conf is already present"
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
ExecStart=/usr/local/bin/lnd\
 --configfile=/home/bitcoin/.lnd/${prefix}lnd.conf
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${prefix}lnd.service
  sudo systemctl enable ${prefix}lnd 
  echo "# Enabled the ${prefix}lnd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${prefix}lnd
    echo "# Started the ${prefix}lnd.service"
  fi

  echo
  echo "# Adding aliases"
  echo "\
alias ${prefix}lncli=\"sudo -u bitcoin /usr/local/bin/lncli\
 --rpcserver localhost:1${portprefix}009\"\
" | sudo tee -a /home/admin/_aliases.sh

  echo
  echo "# The installed LND version is: $(sudo -u bitcoin /usr/local/bin/lnd --version)"
  echo   
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases.sh"
  echo "# Monitor the ${prefix}lnd with:"
  echo "sudo journalctl -fu ${prefix}lnd"
  echo "sudo systemctl status ${prefix}lnd"
  echo "# logs:"
  echo "sudo tail -f /home/bitcoin/.lnd/logs/bitcoin/${CHAIN}/lnd.log"
  echo "# for the command line options use"
  echo "${prefix}lncli help"
  echo

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  removeParallelService
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1