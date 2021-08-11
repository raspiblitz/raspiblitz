#!/bin/bash
# https://github.com/ZmnSCPxj/clboss#operating

# https://github.com/ZmnSCPxj/clboss/releases
CLBOSSVERSION="0.10"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove the CLBOSS C-lightning plugin"
  echo "version: v${CLBOSSVERSION}"
  echo "Usage:"
  echo "cln-plugin.clboss.sh [on|off] [testnet|mainnet|signet]"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cln <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

# add default value to raspi config if needed
configEntry="${netprefix}clboss"
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${configEntry}")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${configEntry}'"
  sudo /bin/sh -c "echo '${configEntry}=off' >> /mnt/hdd/raspiblitz.conf"
else
  echo "# default config entry for '${configEntry}' exists"
fi

if [ $1 = on ];then

  if [ ! -f /home/bitcoin/cln-plugins-available/clboss-${CLBOSSVERSION}.tar.gz ];then
   
    # download tarball
    sudo -u bitcoin wget \
     https://github.com/ZmnSCPxj/clboss/releases/download/v${CLBOSSVERSION}/clboss-${CLBOSSVERSION}.tar.gz \
     -O /home/bitcoin/cln-plugins-available/clboss-${CLBOSSVERSION}.tar.gz || exit 1
  fi

  if [ ! -f /home/bitcoin/cln-plugins-available/clboss-${CLBOSSVERSION}/clboss ];then
    # dependencies
    sudo apt install -y build-essential pkg-config libev-dev \
     libcurl4-gnutls-dev libsqlite3-dev dnsutils

    # install
    cd /home/bitcoin/cln-plugins-available/ || exit 1 
    sudo -u bitcoin tar -xvf clboss-${CLBOSSVERSION}.tar.gz
    cd clboss-${CLBOSSVERSION} || exit 1 
    sudo -u bitcoin ./configure && sudo -u bitcoin make
    # sudo make install # installs to /usr/local/bin/clboss
  fi

  # symlink to enable
  if [ ! -L /home/bitcoin/${netprefix}cln-plugins-enabled/clboss ];then
    sudo ln -s /home/bitcoin/cln-plugins-available/clboss-${CLBOSSVERSION}/clboss \
               /home/bitcoin/${netprefix}cln-plugins-enabled
  fi

  # setting value in raspiblitz.conf
  sudo sed -i "s/^${netprefix}clboss=.*/${netprefix}clboss=on/g" /mnt/hdd/raspiblitz.conf

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate clboss"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo "# clboss was installed for $CHAIN"
  echo "# Monitor with:"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log | grep clboss"
  echo "${netprefix}cln clboss-status"
  echo "https://github.com/ZmnSCPxj/clboss#operating"
  
fi

if [ $1 = off ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cln-plugins-enabled/clboss
  
  echo "# Restart the ${netprefix}lightningd.service to deactivate clboss"
  sudo systemctl restart ${netprefix}lightningd

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cln-plugins-available/clboss*
    sudo rm -f /usr/local/bin/clboss
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}clboss=.*/${netprefix}clboss=off/g" /mnt/hdd/raspiblitz.conf
  echo "# clboss was uninstalled for $CHAIN"

fi
