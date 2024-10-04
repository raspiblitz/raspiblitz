#!/bin/bash
# https://github.com/ZmnSCPxj/clboss#operating

# https://github.com/ZmnSCPxj/clboss/releases
# https://github.com/ZmnSCPxj/clboss/commits/master
CLBOSSVERSION="159ef70278100ab6fda4e625259f2a52b791979a"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install or remove the CLBOSS Core Lightning plugin"
  echo "version: v${CLBOSSVERSION}"
  echo "Usage:"
  echo "cl-plugin.clboss.sh [on|off] [mainnet|testnet] <latest>"
  echo "cl-plugin.clboss.sh info"
  echo "cl-plugin.clboss.sh update"
  echo
  exit 1
fi

if [ $# -gt 2 ] && [ $3 = latest ]; then
  CLBOSSVERSION=""
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

function buildFromSource() {
  version=$1
  # dependencies
  sudo apt install -y build-essential pkg-config libev-dev \
    libcurl4-gnutls-dev libsqlite3-dev dnsutils
  sudo apt install -y git automake autoconf-archive libtool

  # download
  cd /home/bitcoin/cl-plugins-available/ || exit 1
  sudo -u bitcoin git clone https://github.com/ZmnSCPxj/clboss
  cd clboss || exit 1
  if [[ -v version && -n "$version" ]]; then
    sudo -u bitcoin git reset --hard ${version}
  fi

  # build
  sudo -u bitcoin autoreconf -i
  sudo -u bitcoin ./configure && sudo -u bitcoin make
  # sudo make install # optional - installs to /usr/local/bin/clboss
}

if [ "$1" = on ]; then

  if [ ! -f /home/bitcoin/cl-plugins-available/clboss/clboss ]; then

    buildFromSource ${CLBOSSVERSION}

  fi

  # refresh symlink to enable
  sudo rm /home/bitcoin/${netprefix}cl-plugins-enabled/clboss 2>/dev/null
  sudo ln -s /home/bitcoin/cl-plugins-available/clboss/clboss \
    /home/bitcoin/${netprefix}cl-plugins-enabled/

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

  exit 0
fi

if [ "$1" = off ]; then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/clboss

  echo "# Restarting the ${netprefix}lightningd.service to deactivate clboss"
  sudo systemctl restart ${netprefix}lightningd

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cl-plugins-available/clboss*
    sudo rm -f /usr/local/bin/clboss
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clboss "off"
  echo "# clboss was uninstalled for $CHAIN"

  exit 0
fi

if [ "$1" = update ]; then
  if [ ! -f /home/bitcoin/cl-plugins-available/clboss/clboss ]; then
    /home/admin/config.scrips/cl-plugin/clboss.sh on "${CHAIN}"
    exit 0
  else
    sudo rm -rf /home/bitcoin/cl-plugins-available/clboss

    buildFromSource

    echo "# clboss was updated to the latest master commit"
    echo "# Restarting ${netprefix}lightningd to activate"
    sudo systemctl restart ${netprefix}lightningd

    exit 0
  fi
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
