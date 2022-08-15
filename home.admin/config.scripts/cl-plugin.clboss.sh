#!/bin/bash
# https://github.com/ZmnSCPxj/clboss#operating

# https://github.com/ZmnSCPxj/clboss/releases
CLBOSSVERSION="0.13A"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove the CLBOSS Core Lightning plugin"
  echo "version: v${CLBOSSVERSION}"
  echo "Usage:"
  echo "cl-plugin.clboss.sh [on|off] [testnet|mainnet|signet]"
  echo "cl-plugin.clboss.sh [info]"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

if [ "$1" = info ]; then
	whiptail --title " CLBOSS WARNING " \
    --yes-button "Install" \
		--no-button "Cancel" \
		--yesno "
The goal of CLBOSS is to make the node able to pay and receive payments
on the lightning network reliably without needing active management.
It is not a tool to run a profitable lightning node and it can lose some sats on fees.

CLBOSS does the following automatically:
- Open channels to other, useful nodes when fees are low and there are onchain funds
- Acquire incoming capacity via boltz.exchange swaps (these funds return onchain)
- Rebalance open channels by self-payment (including JIT rebalancer)
- Set forwarding fees so that they're competitive to other nodes

Links with more info:
https://github.com/rootzoll/raspiblitz/blob/dev/FAQ.cl.md#clboss
https://github.com/ZmnSCPxj/clboss#operating
" 0 0
fi


if [ "$1" = on ];then

  if [ ! -f /home/bitcoin/cl-plugins-available/clboss-${CLBOSSVERSION}.tar.gz ];then

    # download tarball
    sudo -u bitcoin wget \
     https://github.com/ZmnSCPxj/clboss/releases/download/${CLBOSSVERSION}/clboss-${CLBOSSVERSION}.tar.gz \
     -O /home/bitcoin/cl-plugins-available/clboss-${CLBOSSVERSION}.tar.gz || exit 1
  fi

  if [ ! -f /home/bitcoin/cl-plugins-available/clboss-${CLBOSSVERSION}/clboss ];then
    # dependencies
    sudo apt install -y build-essential pkg-config libev-dev \
     libcurl4-gnutls-dev libsqlite3-dev dnsutils

    # install
    cd /home/bitcoin/cl-plugins-available/ || exit 1
    sudo -u bitcoin tar -xvf clboss-${CLBOSSVERSION}.tar.gz
    cd clboss-${CLBOSSVERSION} || exit 1
    sudo -u bitcoin ./configure && sudo -u bitcoin make
    # sudo make install # installs to /usr/local/bin/clboss
  fi

  # symlink to enable
  if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/clboss ];then
    sudo ln -s /home/bitcoin/cl-plugins-available/clboss-${CLBOSSVERSION}/clboss \
               /home/bitcoin/${netprefix}cl-plugins-enabled
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clboss "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate clboss"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo "# clboss was installed for $CHAIN"
  echo "# Monitor with:"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log | grep clboss"
  echo "${netprefix}cl clboss-status"
  echo "https://github.com/ZmnSCPxj/clboss#operating"

fi

if [ "$1" = off ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/clboss

  echo "# Restart the ${netprefix}lightningd.service to deactivate clboss"
  sudo systemctl restart ${netprefix}lightningd

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cl-plugins-available/clboss*
    sudo rm -f /usr/local/bin/clboss
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clboss "off"
  echo "# clboss was uninstalled for $CHAIN"

fi
