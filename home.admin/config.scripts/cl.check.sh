#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo
  echo "# script to check CL states"
  echo "# cl.check.sh basic-setup"
  echo "# cl.check.sh prestart [mainnet|testnet|signet]"
  echo
  exit 1
fi

# load variables
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

######################################################################
# PRESTART
# is executed by systemd cl services everytime before cl is started
# so it tries to make sure the config is in valid shape
######################################################################

if [ $(grep -c "^sparko" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/sparko ]\
    || [ "$(eval echo \$${netprefix}sparko)" != "on" ]; then
    echo "# The Sparko plugin is not present but in config"
    sed -i "/^sparko/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/sparko
    sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=off/g" /mnt/hdd/raspiblitz.conf
  fi
fi

if [ $(grep -c "^http-pass" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ]\
    || [ "${clHTTPplugin}" != "on" ]; then
    echo "# The clHTTPplugin is not present but in config"
    sed -i "/^http-pass/d" ${CLCONF}
    rm -rf /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin
    sed -i "s/^clHTTPplugin=.*/clHTTPplugin=off/g" /mnt/hdd/raspiblitz.conf
  fi
fi

if [ $(grep -c "^feeadjuster" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ]\
    || [ "$(eval echo \$${netprefix}feeadjuster)" != "on" ]; then
    echo "# The feeadjuster plugin is not present but in config"
    sed -i "/^feeadjuster/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py
    sed -i "s/^${netprefix}feeadjuster=.*/${netprefix}feeadjuster=off/g" /mnt/hdd/raspiblitz.conf
  fi
fi