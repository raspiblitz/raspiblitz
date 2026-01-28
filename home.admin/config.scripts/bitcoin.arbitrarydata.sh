#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to manage Bitcoin arbitrary data restrictions (BIP 110 aligned)"
  echo "bitcoin.arbitrarydata.sh [status|on|off|menu]"
  echo
  echo "This script manages policy settings that restrict arbitrary data in Bitcoin transactions:"
  echo "- datacarriersize=83 (limits OP_RETURN to 83 bytes)"
  echo "- permitbaremultisig=0 (disables bare multisig transactions)"
  echo
  exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null

BITCOIN_CONF="/mnt/hdd/app-data/bitcoin/bitcoin.conf"

# check status
if [ "$1" = "status" ]; then
  
  isConfigured=0
  
  if [ -f "${BITCOIN_CONF}" ]; then
    # check if both settings are present and set correctly
    datacarriersize=$(grep "^datacarriersize=" ${BITCOIN_CONF} 2>/dev/null | cut -d= -f2)
    permitbaremultisig=$(grep "^permitbaremultisig=" ${BITCOIN_CONF} 2>/dev/null | cut -d= -f2)
    
    if [ "${datacarriersize}" = "83" ] && [ "${permitbaremultisig}" = "0" ]; then
      isConfigured=1
    fi
  fi
  
  echo "isConfigured=${isConfigured}"
  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then
  
  # get current status
  source <(/home/admin/config.scripts/bitcoin.arbitrarydata.sh status)
  
  if [ ${isConfigured} -eq 1 ]; then
    STATUS="ON"
    STATUS_INFO="Arbitrary data restrictions are currently ACTIVE.\n\n"
  else
    STATUS="OFF"
    STATUS_INFO="Arbitrary data restrictions are currently DISABLED.\n\n"
  fi
  
  whiptail --title " Bitcoin Arbitrary Data Restriction " --msgbox "${STATUS_INFO}This feature implements policy settings aligned with BIP 110 to prevent blockchain bloat from arbitrary data storage.\n\nWhen enabled, it restricts:\n- OP_RETURN outputs to 83 bytes (datacarriersize=83)\n- Bare multisig transactions (permitbaremultisig=0)\n\nThese are Bitcoin Core policy options (not consensus rules) that help protect against spam while maintaining compatibility with the network.\n\nCurrent Status: ${STATUS}\n\nFor more information about BIP 110:\nhttps://github.com/dathonohm/bips/blob/reduced-data/bip-0110.mediawiki" 22 78
  
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  
  echo "# Enabling Bitcoin arbitrary data restrictions..."
  
  if [ ! -f "${BITCOIN_CONF}" ]; then
    echo "# ERROR: Bitcoin configuration file not found at ${BITCOIN_CONF}"
    exit 1
  fi
  
  # Clean up any existing settings first to avoid conflicts
  sudo sed -i "/^datacarriersize=/d" ${BITCOIN_CONF}
  sudo sed -i "/^permitbaremultisig=/d" ${BITCOIN_CONF}
  sudo sed -i "/^# BIP 110 aligned: Restrict arbitrary data in transactions/d" ${BITCOIN_CONF}
  
  # Add the new settings
  echo "" | sudo tee -a ${BITCOIN_CONF}
  echo "# BIP 110 aligned: Restrict arbitrary data in transactions" | sudo tee -a ${BITCOIN_CONF}
  echo "datacarriersize=83" | sudo tee -a ${BITCOIN_CONF}
  echo "permitbaremultisig=0" | sudo tee -a ${BITCOIN_CONF}
  
  # Store setting in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set arbitraryDataRestriction "on"
  
  echo "# Bitcoin arbitrary data restrictions have been enabled."
  echo "# Bitcoin needs to be restarted for changes to take effect."
  echo "# You can restart with: sudo systemctl restart bitcoind"
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  
  echo "# Disabling Bitcoin arbitrary data restrictions..."
  
  if [ ! -f "${BITCOIN_CONF}" ]; then
    echo "# ERROR: Bitcoin configuration file not found at ${BITCOIN_CONF}"
    exit 1
  fi
  
  # Remove or comment out the settings
  sudo sed -i "/^datacarriersize=/d" ${BITCOIN_CONF}
  sudo sed -i "/^permitbaremultisig=/d" ${BITCOIN_CONF}
  sudo sed -i "/^# BIP 110 aligned: Restrict arbitrary data in transactions/d" ${BITCOIN_CONF}
  
  # Update setting in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set arbitraryDataRestriction "off"
  
  echo "# Bitcoin arbitrary data restrictions have been disabled."
  echo "# Bitcoin needs to be restarted for changes to take effect."
  echo "# You can restart with: sudo systemctl restart bitcoind"
  
  exit 0
fi

echo "# FAIL: Unknown parameter '$1'"
exit 1
