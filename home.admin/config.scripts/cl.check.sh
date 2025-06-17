#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo
  echo "# script to check CL states"
  echo "# cl.check.sh basic-setup"
  echo "# cl.check.sh prestart [mainnet|testnet|signet]"
  echo "# cl.check.sh poststart [mainnet|testnet|signet]"
  echo
  exit 1
fi

# load variables
source /mnt/hdd/app-data/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

######################################################################
# PRESTART
# is executed by systemd cl services everytime BEFORE cl is started
# so it tries to make sure the config is in valid shape
######################################################################

if [ "$1" == "prestart" ]; then

  # make sure plugins are loaded https://github.com/rootzoll/raspiblitz/issues/2953
  if [ $(grep -c "^plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled" <${CLCONF}) -eq 0 ]; then
    echo "plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled" | tee -a ${CLCONF}
  fi

  # do not announce 127.0.0.1 https://github.com/rootzoll/raspiblitz/issues/2634
  if [ $(grep -c "^announce-addr=127.0.0.1" <${CLCONF}) -gt 0 ]; then
    sed -i "/^announce-addr=127.0.0.1/d" ${CLCONF}
  fi

  if [ $(grep -c "^clboss" <${CLCONF}) -gt 0 ]; then
    if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/clboss ] || [ "$(eval echo \$${netprefix}clboss)" != "on" ]; then
      echo "# The clboss plugin is not present but in config"
      sed -i "/^clboss/d" ${CLCONF}
      rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/clboss
    fi
  fi

  if [ $(grep -c "^http-pass" <${CLCONF}) -gt 0 ]; then
    if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ] || [ "${clHTTPplugin}" != "on" ]; then
      echo "# The clHTTPplugin is not present but in config"
      sed -i "/^http-pass/d" ${CLCONF}
      rm -rf /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin
    fi
  fi

  if [ $(grep -c "^feeadjuster" <${CLCONF}) -gt 0 ]; then
    if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ] || [ "$(eval echo \$${netprefix}feeadjuster)" != "on" ]; then
      echo "# The feeadjuster plugin is not present but in config"
      sed -i "/^feeadjuster/d" ${CLCONF}
      rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py
    fi
  fi

  # https://github.com/rootzoll/raspiblitz/issues/3007
  # add for test networks as well if needed on mainnet
  if [ "${blitzapi}" = "on" ] ||
    [ "${LNBitsFunding}" = "${netprefix}cl" ] ||
    [ "${BTCPayServer}" = "on" ]; then
    if [ $(grep -c "^rpc-file-mode=0660" <${CLCONF}) -eq 0 ]; then
      echo "rpc-file-mode=0660" | tee -a ${CLCONF}
    fi
  fi

  if [ -f /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc ] ||
    [ -f /usr/local/libexec/c-lightning/plugins/cln-grpc ] ||
    [ "$(eval echo \$${netprefix}cln-grpc-port)" != "off" ]; then
    if [ $(grep -c "^grpc-port" <${CLCONF}) -eq 0 ]; then
      echo "# Create grpc-port entry"
      echo "grpc-port=${portprefix}4772" | tee -a ${CLCONF}
    fi
    echo "# Make sure that the correct GRPC port is used for $NETWORK"
    sed -i "s/^grpc-port=.*/grpc-port=${portprefix}4772/g" ${CLCONF}
  else
    echo "# The cln-grpc plugin is not present but in config"
    sed -i "/^grpc-port/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
  fi

  if [ -f /home/bitcoin/${netprefix}cl-plugins-enabled/clnrest ] ||
    [ -f /usr/local/libexec/c-lightning/plugins/clnrest ]; then
    if [ $(grep -c "^clnrest-port" <${CLCONF}) -eq 0 ]; then
      echo "# Create clnrest-port entry"
      echo "clnrest-port=${portprefix}7378" | tee -a ${CLCONF}
    fi
    if [ $(grep -c "^clnrest-host" <${CLCONF}) -eq 0 ]; then
      echo "# Create clnrest-host entry"
      echo "clnrest-host=0.0.0.0" | tee -a ${CLCONF}
    fi
    echo "# Make sure that the correct clnrest port is used for $NETWORK"
    sed -i "s/^clnrest-port=.*/clnrest-port=${portprefix}7378/g" ${CLCONF}
    sed -i "s/^clnrest-host=.*/clnrest-host=0.0.0.0/g" ${CLCONF}
  else
    echo "# The clnrest plugin is not present but in config"
    sed -i "/^clnrest-port/d" ${CLCONF}
    sed -i "/^clnrest-host/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/clnrest
  fi

  exit 0
fi

######################################################################
# POSTSTART
# is executed by systemd cl services everytime AFTER cl is started
# takes care of things that are just available when CL is running
######################################################################

if [ "$1" == "poststart" ]; then

  # log info
  info=$(ls -la /mnt/hdd/app-data/.lightning/bitcoin/lightning-rpc)
  logger "${info}"

  exit 0
fi

echo "# Unkonwn Parameter $1 or missing"
exit 1
