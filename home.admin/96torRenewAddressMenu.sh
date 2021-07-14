#!/bin/bash

# include lib
#. /home/admin/config.scripts/tor.functions.lib
. /home/admin/raspi-tor/config.scripts/tor.functions.lib

# services default values
if [ ${#sshTor} -eq 0 ]; then sshTor="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#BTCRPCexplorer} -eq 0 ]; then BTCRPCexplorer="off"; fi
if [ ${#specter} -eq 0 ]; then specter="off"; fi
if [ ${#BTCPayServer} -eq 0 ]; then BTCPayServer="off"; fi
if [ ${#LNBits} -eq 0 ]; then LNBits="off"; fi
if [ ${#mempoolExplorer} -eq 0 ]; then mempoolExplorer="off"; fi
if [ ${#thunderhub} -eq 0 ]; then thunderhub="off"; fi
if [ ${#lit} -eq 0 ]; then lit="off"; fi

if [ ${#web80OnionAuth} -eq 0 ]; then web80OnionAuth="off"; fi
if [ ${#sshTorOnionAuth} -eq 0 ]; then sshTorOnionAuth="off"; fi
if [ ${#rtlWebinterfaceOnionAuth} -eq 0 ]; then rtlWebinterfaceOnionAuth="off"; fi
if [ ${#BTCRPCexplorerOnionAuth} -eq 0 ]; then BTCRPCexplorerOnionAuth="off"; fi
if [ ${#specterOnionAuth} -eq 0 ]; then specterOnionAuth="off"; fi
if [ ${#BTCPayServerOnionAuth} -eq 0 ]; then BTCPayServerOnionAuth="off"; fi
if [ ${#LNBitsOnionAuth} -eq 0 ]; then LNBitsOnionAuth="off"; fi
if [ ${#mempoolExplorerOnionAuth} -eq 0 ]; then mempoolExplorerOnionAuth="off"; fi
if [ ${#thunderhubOnionAuth} -eq 0 ]; then thunderhubOnionAuth="off"; fi
if [ ${#litOnionAuth} -eq 0 ]; then litOnionAuth="off"; fi

source ${CONF}

OPTIONS=()
if [ "${network}" == "bitcoin" ]; then
  OPTIONS+=(a 'Bitcoin Daemon' OFF)
  OPTIONS+=(b 'Bitcoin RPC' OFF)
  HEIGHT=$((HEIGHT+2))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+2))
fi
OPTIONS+=(c 'Blitz-WebUI' OFF)
HEIGHT=$((HEIGHT+1))
CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
if [ "${sshTor}" == "on" ]; then
  OPTIONS+=(d 'SSH' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${rtlWebinterface}" == "on" ]; then
  OPTIONS+=(e 'RTL Webinterface' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(f 'Thunderhub' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${lit}" == "on" ]; then
  OPTIONS+=(g 'LIT (loop, pool, faraday)' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(h 'BTCPayServer' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${LNBits}" == "on" ]; then
  OPTIONS+=(i 'LNbits' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCRPCexplorer}" == "on" ]; then
  OPTIONS+=(j 'BTC-RPC-Explorer' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${specter}" == "on" ]; then
  OPTIONS+=(k 'Cryptoadvance Specter' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(l 'Mempool Space' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

TITLE="Renew onion addres"
CHOICES=$(dialog --title "$TITLE" \
          --checklist ' use spacebar to activate/de-activate ' \
          22 45 15  "${OPTIONS[@]}" 2>&1 >/dev/tty)

dialogcancel=$?
echo "done dialog"
clear

echo "dialogcancel(${dialogcancel})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
elif [ ${dialogcancel} -eq 255 ]; then
  echo "ESC pressed"
  exit 1
fi

check=$(echo "${CHOICES}" | grep -c "a")
if [ ${check} -eq 1 ]; then
  echo "Bitcoin Daemon setting CHANGED .."
  sudo rm -f /mnt/hdd/bitcoin/onion_v3_private_key
  sudo systemctl restart bitcoind
else
  echo "Bitcoin Daemon setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "b")
if [ ${check} -eq 1 ]; then
  echo "Bitcoin RPC setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew bitcoin
else
  echo "Bitcoin RPC setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then
  echo "Blitz-WebUI setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew web80
  if [ "${web80OnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on web80
  fi
else
  echo "Blitz-WebUI setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "d")
if [ ${check} -eq 1 ]; then
  echo "SSH setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew ssh
  if [ "${sshTorOnionAuth}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on ssh
  fi
else
  echo "SSH setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "e")
if [ ${check} -eq 1 ]; then
  echo "RTL setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew rtl
  if [ "${rtlWebinterfaceOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on rtl
  fi
else
  echo "RTL setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "f")
if [ ${check} -eq 1 ]; then
  echo "Thunderhub setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew thunderhub
  if [ "${thunderhubOnionAuth}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on thunderhub
  fi
else
  echo "Thunderhub setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "g")
if [ ${check} -eq 1 ]; then
  echo "LIT setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew lit
  if [ "${litOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on lit
  fi
else
  echo "LIT setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "h")
if [ ${check} -eq 1 ]; then
  echo "BTCPayServer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew btcpay
  if [ "${BTCPayServerOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on btcpay
  fi
else
  echo "BTCPayServer setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "i")
if [ ${check} -eq 1 ]; then
  echo "LNBits setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew lnbits
  if [ "${LNBitsOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on lnbits
  fi
else
  echo "LNBits setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "j")
if [ ${check} -eq 1 ]; then
  echo "BTC-RPC-Explorer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew btcrpcexplorer
  if [ "${BTCRPCexplorerOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on btcrpcexplorer
  fi
else
  echo "BTC-RPC-Explorer setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "k")
if [ ${check} -eq 1 ]; then
  echo "Specter setting CHANGED .."
  ${ONION_SERVICE_SCRIPT}
  if [ "${specterOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on cryptopadvance-specter
  fi
else
  echo "Specter setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then
  echo "Mempool setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} renew mempool
  if [ "${mempoolExplorerOnionAuth}" == "on" ]; then
    ${ONION_SERVICE_SCRIPT} auth on mempool
  fi
else
  echo "Mempool setting unchanged."
fi

restarting_tor ${SOURCE_SCRIPT}
