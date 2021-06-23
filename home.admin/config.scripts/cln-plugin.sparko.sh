#!/bin/bash

# explanation on paths https://github.com/ElementsProject/lightning/issues/4223
# built-in path dir: /usr/local/libexec/c-lightning/plugins/
# added --plugin-dir=/home/bitcoin/cln-plugins-enabled

SPARKOVERSION="v2.7"

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove, connect or get info about the Sparko plugin for C-lightning"
  echo "version: $SPARKOVERSION"
  echo "Usage:"
  echo "cln-plugin.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet]"
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
  sudo wget https://github.com/fiatjaf/sparko/releases/download/${SPARKOVERSION}/sparko_${DISTRO}\
   -O /home/bitcoin/cln-plugins-enabled/sparko
  # make executable
  sudo chmod +x /home/bitcoin/cln-plugins-enabled/sparko
  
  echo "# Editing /home/bitcoin/.lightning/${netprefix}config"
  echo "# See: https://github.com/fiatjaf/sparko#how-to-use"
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  masterkeythatcandoeverything=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  secretaccesskeythatcanreadstuff=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  verysecretkeythatcanpayinvoices=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  keythatcanlistentoallevents=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
  echo "
sparko-host=0.0.0.0
sparko-port=${portprefix}9000
#sparko-tls-path=
sparko-login=blitz:$PASSWORD_B
sparko-keys=${masterkeythatcandoeverything}; ${secretaccesskeythatcanreadstuff}: getinfo, listchannels, listnodes; ${verysecretkeythatcanpayinvoices}: pay; ${keythatcanlistentoallevents}: stream
" | sudo tee -a /home/bitcoin/.lightning/${netprefix}config

  #TODO self signed cert https://github.com/fiatjaf/sparko#how-to-use

  echo "# Editing /etc/systemd/system/${netprefix}lightningd.service"
  sudo sed -i "s#^ExecStart=.*#ExecStart=/usr/local/bin/lightningd\
 --conf=/home/bitcoin/.lightning/${netprefix}config\
 --plugin=/home/bitcoin/cln-plugins-enabled/sparko#g"\
  /etc/systemd/system/${netprefix}lightningd.service

  sudo systemctl daemon-reload
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo "# Allowing port ${portprefix}9000 through the firewall"
  sudo ufw allow "${portprefix}9000" comment "${netprefix}sparko"

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=on/g" /mnt/hdd/raspiblitz.conf

  sleep 5
  sudo cat /home/bitcoin/.lightning/${clnetwork}/cl.log | grep sparko
  netstat -tulpn | grep "${portprefix}9000"

  echo "# Sparko was installed"
  echo "# Monitor with:"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${clnetwork}/cl.log"
fi

if [ $1 = off ];then
  echo "# Editing /home/bitcoin/.lightning/${netprefix}config"
  sudo sed -i "/^sparko/d" /home/bitcoin/.lightning/${netprefix}config

  echo "# Editing /etc/systemd/system/${netprefix}lightningd.service"
  sudo sed -i "s#^ExecStart=*#ExecStart=/usr/local/bin/lightningd\
 --conf=/home/bitcoin/.lightning/${netprefix}config#"\
  /etc/systemd/system/${netprefix}lightningd.service
  sudo systemctl daemon-reload
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    sudo systemctl restart ${netprefix}lightningd
  fi
  echo "# Deny port ${portprefix}9000 through the firewall"
  sudo ufw deny "${portprefix}9000"
  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm /home/bitcoin/cln-plugins-enabled/${netprefix}sparko
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=off/g" /mnt/hdd/raspiblitz.conf
  echo "# Sparko was uninstalled"
fi
