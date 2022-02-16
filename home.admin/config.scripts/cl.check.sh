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

# make sure plugins are loaded https://github.com/rootzoll/raspiblitz/issues/2953
if [ $(grep -c "^plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled" < ${CLCONF}) -eq 0 ];then
  echo "plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled" | tee -a ${CLCONF}
fi

# do not announce 127.0.0.1 https://github.com/rootzoll/raspiblitz/issues/2634
if [ $(grep -c "^announce-addr=127.0.0.1" < ${CLCONF}) -gt 0 ];then
  sed -i "/^announce-addr=127.0.0.1/d" ${CLCONF}
fi

if [ $(grep -c "^sparko" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/sparko ]\
    || [ "$(eval echo \$${netprefix}sparko)" != "on" ]; then
    echo "# The Sparko plugin is not present but in config"
    sed -i "/^sparko/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/sparko
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}sparko "off"
  fi
fi

if [ $(grep -c "^http-pass" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ]\
    || [ "${clHTTPplugin}" != "on" ]; then
    echo "# The clHTTPplugin is not present but in config"
    sed -i "/^http-pass/d" ${CLCONF}
    rm -rf /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin
    /home/admin/config.scripts/blitz.conf.sh set clHTTPplugin "off"
  fi
fi

if [ $(grep -c "^feeadjuster" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ]\
    || [ "$(eval echo \$${netprefix}feeadjuster)" != "on" ]; then
    echo "# The feeadjuster plugin is not present but in config"
    sed -i "/^feeadjuster/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "off"
  fi
fi

if [ ${CHAIN} = "testnet" ]; then 
  clrpcsubdir="/testnet"
elif [ ${CHAIN} = "signet" ]; then 
  clrpcsubdir="/signet"
fi
# make the lightning-rpc socket group readable
chmod 770 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}
chmod 660 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}/lightning-rpc