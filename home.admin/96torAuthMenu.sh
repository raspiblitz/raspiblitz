#!/bin/bash

# include lib
. /home/admin/config.scripts/tor.functions.lib

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
OPTIONS+=(w 'Blitz-WebUI' ${web80OnionAuth})
HEIGHT=$((HEIGHT+1))
CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
if [ "${sshTor}" == "on" ]; then
  OPTIONS+=(h 'SSH' ${sshTorOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${rtlWebinterface}" == "on" ]; then
  OPTIONS+=(r 'RTL Webinterface' ${rtlWebinterfaceOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(t 'ThunderHub' ${thunderhubOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${lit}" == "on" ]; then
  OPTIONS+=(l 'LIT (loop, pool, faraday)' ${litOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(p 'BTCPayServer' ${BTCPayServerOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${LNBits}" == "on" ]; then
  OPTIONS+=(i 'LNbits' ${LNBitsOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCRPCexplorer}" == "on" ]; then
  OPTIONS+=(b 'BTC-RPC-Explorer' ${BTCRPCexplorerOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${specter}" == "on" ]; then
  OPTIONS+=(s 'Cryptoadvance Specter' ${specterOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(m 'Mempool Space' ${mempoolExplorerOnionAuth})
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}" / 3))

TITLE="Auth for services"
CHOICES=$(dialog --title "$TITLE" \
          --checklist ' use spacebar to activate/de-activate ' \
          22 45 15 "${OPTIONS[@]}" 2>&1 >/dev/tty)

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

choice="off"; check=$(echo "${CHOICES}" | grep -c "w")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${web80OnionAuth}" != "${choice}" ]; then
  echo "Blitz WebUI setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} web80
else
  echo "Blitz WebUI setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "h")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${sshOnionAuth}" != "${choice}" ]; then
  echo "SSH setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} ssh
else
  echo "SSH setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${rtlWebinterfaceOnionAuth}" != "${choice}" ]; then
  echo "RTL setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} rtl
else
  echo "RTL setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "b")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCRPCexplorerOnionAuth}" != "${choice}" ]; then
  echo "BTC-RPC-explorer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} btc-rpc-explorer
else
  echo "BTC-RPC-explorer setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "s")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${specterOnionAuth}" != "${choice}" ]; then
  echo "Cryptoadvance-specterRTL setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} cryptoadvance-specter
else
  echo "Cryptoadvance-specter setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${thunderhubOnionAuth}" != "${choice}" ]; then
  echo "Thunderhub setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} thunderhub
else
  echo "Thunderhub setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "p")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCPayServerOnionAuth}" != "${choice}" ]; then
  echo "BTCPayServer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} btcpay
else
  echo "BTCPayServer setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "i")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${LNBitsOnionAuth}" != "${choice}" ]; then
  echo "LNBits setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} lnbits
else
  echo "LNBits setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "m")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${mempoolExplorerOnionAuth}" != "${choice}" ]; then
  echo "Mempool setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} mempool
else
  echo "Mempool setting unchanged."
fi

choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${litOnionAuth}" != "${choice}" ]; then
  echo "LIT setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} auth ${choice} lit
else
  echo "LIT setting unchanged."
fi
