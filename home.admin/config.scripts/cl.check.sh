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
  fi
fi

if [ $(grep -c "^clboss" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/clboss ]\
    || [ "$(eval echo \$${netprefix}clboss)" != "on" ]; then
    echo "# The clboss plugin is not present but in config"
    sed -i "/^clboss/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/clboss
  fi
fi

if [ $(grep -c "^http-pass" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ]\
    || [ "${clHTTPplugin}" != "on" ]; then
    echo "# The clHTTPplugin is not present but in config"
    sed -i "/^http-pass/d" ${CLCONF}
    rm -rf /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin
  fi
fi

if [ $(grep -c "^feeadjuster" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ]\
    || [ "$(eval echo \$${netprefix}feeadjuster)" != "on" ]; then
    echo "# The feeadjuster plugin is not present but in config"
    sed -i "/^feeadjuster/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py
  fi
fi

if [ "${LNBitsFunding}" = "${netprefix}cl" ]; then
  # https://github.com/rootzoll/raspiblitz/issues/3007
  if [ $(grep -c "^rpc-file-mode=0660" < ${CLCONF}) -eq 0 ]; then
    echo "rpc-file-mode=0660" | tee -a ${CLCONF}
  fi
fi

if [ "${BTCPayServer}" = "on" ] && [ "${CHAIN}" = "mainnet" ] ; then
  # https://github.com/rootzoll/raspiblitz/issues/3007
  if [ $(grep -c "^rpc-file-mode=0660" < ${CLCONF}) -eq 0 ]; then
    echo "rpc-file-mode=0660" | tee -a ${CLCONF}
  fi
fi

if [ $(grep -c "^grpc-port" < ${CLCONF}) -gt 0 ];then
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc ]\
    || [ "$(eval echo \$${netprefix}cln-grpc-port)" = "off" ]; then
    echo "# The cln-grpc plugin is not present but in config"
    sed -i "/^grpc-port/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
  fi
fi
