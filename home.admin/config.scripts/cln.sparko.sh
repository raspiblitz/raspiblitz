#!/bin/bash

# explanation on paths https://github.com/ElementsProject/lightning/issues/4223
# built-in path dir: /usr/local/libexec/c-lightning/plugins/

SPARKOVERSION="v2.5"

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove, connect or get info about the Sparko plugin for C-lightning"
  echo "version: $SPARKOVERSION"
  echo "Usage:"
  echo "cln.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet]"
  echo
  exit 1
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  netprefix="t"
  clnetwork="testnet"
  portprefix=1
elif [ ${CHAIN} = signet ];then
  netprefix="s"
  clnetwork="signet"
  portprefix=3
elif [ ${CHAIN} = mainnet ];then
  netprefix=""
  clnetwork="bitcoin"
  portprefix=""
fi

# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}sparko=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}sparko=off" >> /mnt/hdd/raspiblitz.conf
fi

if [ $1 = on ];then
  echo "# Detect CPU architecture ..."
  isARM=$(uname -m | grep -c 'arm')
  isAARCH64=$(uname -m | grep -c 'aarch64')
  isX86_64=$(uname -m | grep -c 'x86_64')
      
  if [ ${isARM} -eq 1 ] ; then
    DISTRO="linux-arm"
  elif [ ${isAARCH64} -eq 1 ] ; then
    DISTRO="linux_arm"
  elif [ ${isX86_64} -eq 1 ] ; then
    DISTRO="linux_amd64"
  fi
  
  # download binary
  sudo wget https://github.com/fiatjaf/sparko/releases/download/${SPARKOVERSION}/sparko_${DISTRO} -O /usr/local/libexec/c-lightning/plugins/sparko
  # make executable
  sudo chmod +x /usr/local/libexec/c-lightning/plugins/sparko
  
  echo "# Editing /home/bitcoin/.lightning/${netprefix}config"
  echo "# See: https://github.com/fiatjaf/sparko#how-to-use"
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  masterkeythatcandoeverything=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  secretaccesskeythatcanreadstuff=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  verysecretkeythatcanpayinvoices=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  keythatcanlistentoallevents=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  echo "
sparko-host=0.0.0.0
sparko-port=${portprefix}9737
sparko-tls-path=/mnt/hdd/app-data/nginx/tls.cert
sparko-login=raspiblitz:$PASSWORD_B
sparko-keys=${masterkeythatcandoeverything}; ${secretaccesskeythatcanreadstuff}: getinfo, listchannels, listnodes; ${verysecretkeythatcanpayinvoices}: pay; ${keythatcanlistentoallevents}: stream
" | sudo tee -a /home/bitcoin/.lightning/${netprefix}config

  echo "# Editing /etc/systemd/system/${netprefix}lightningd.service"
  sudo sed -i "s#^ExecStart=.*#ExecStart=/usr/local/bin/lightningd\
 --conf=/home/bitcoin/.lightning/${netprefix}config\
 --plugin=/usr/local/libexec/c-lightning/plugins/sparko#g"\
  /etc/systemd/system/${netprefix}lightningd.service

  sudo systemctl daemon-reload
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    sudo systemctl restart ${netprefix}lightningd
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=on/g" /mnt/hdd/raspiblitz.conf

  echo "# Sparko was installed"
  echo "# Monitor with:"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${clnetwork}/cl.log"
fi

if [ $1 = off ];then
  echo "# Editing /home/bitcoin/.lightning/${netprefix}config"
  sudo sed -i "s/^sparko*/d" /home/bitcoin/.lightning/${netprefix}config

  echo "# Editing /etc/systemd/system/${netprefix}lightningd.service"
  sed -i "s#^ExecStart=*#ExecStart=/usr/local/bin/lightningd\
 --conf=/home/bitcoin/.lightning/${netprefix}config#"\
  /etc/systemd/system/${netprefix}lightningd.service
  sudo systemctl daemon-reload
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    sudo systemctl restart ${netprefix}lightningd
  fi
  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm /usr/local/libexec/c-lightning/plugins/sparko
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=off/g" /mnt/hdd/raspiblitz.conf
  echo "# Sparko was uninstalled"
fi
