#!/bin/bash

# include lib
. /home/admin/config.scripts/tor.functions.lib

echo "services default values"
if [ ${#sshTor} -eq 0 ]; then sshTor="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#BTCRPCexplorer} -eq 0 ]; then BTCRPCexplorer="off"; fi
if [ ${#specter} -eq 0 ]; then specter="off"; fi
if [ ${#BTCPayServer} -eq 0 ]; then BTCPayServer="off"; fi
if [ ${#ElectRS} -eq 0 ]; then ElectRS="off"; fi
if [ ${#joinmarket} -eq 0 ]; then joinmarket="off"; fi
if [ ${#LNBits} -eq 0 ]; then LNBits="off"; fi
if [ ${#mempoolExplorer} -eq 0 ]; then mempoolExplorer="off"; fi
if [ ${#thunderhub} -eq 0 ]; then thunderhub="off"; fi
if [ ${#sphinxrelay} -eq 0 ]; then sphinxrelay="off"; fi
if [ ${#lit} -eq 0 ]; then lit="off"; fi

OPTIONS=()

# lnd
# c-lightning

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
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(m 'Electrum Rust Server' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${sphinxrelay}" == "on" ]; then
  OPTIONS+=(n 'Sphinx Relay' OFF)
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

TITLE="Get services credentials (addresses, QR code)"
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

check=$(echo "${CHOICES}" | grep -c "y")
if [ ${check} -eq 1 ]; then
  echo "LND setting CHANGED .."
  #lncli getinfo | jq -r '.uris [0]'
  # https://github.com/rootzoll/raspiblitz/pull/2352#issuecomment-867729234
  source <(/home/admin/config.scripts/network.aliases.sh getvars lnd mainnet)
  ln_getInfo=$($lncli_alias getinfo 2>/dev/null)
  ln_external=$(echo "${ln_getInfo}" | jq -r '.uris' | grep onion | cut -d'"' -f2 | cut -d':' -f1)
else
  echo "LND setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "z")
if [ ${check} -eq 1 ]; then
  echo "C-Lightning setting CHANGED .."
  # https://github.com/rootzoll/raspiblitz/pull/2352#issuecomment-867700419
  source <(/home/admin/config.scripts/network.aliases.sh getvars cln mainnet)
  cln_external=$(echo "$lightningcli_alias getinfo" | grep ".onion" | cut -d= -f2)
else
  echo "C-Lightning setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "a")
if [ ${check} -eq 1 ]; then
  echo "Bitcoin Daemon setting CHANGED .."
  bitcoin-cli getnetworkinfo | jq -r '.localaddresses [0] .address'
else
  echo "Bitcoin Daemon setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "b")
if [ ${check} -eq 1 ]; then
  echo "Bitcoin RPC setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials bitcoin
else
  echo "Bitcoin RPC setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then
  echo "Blitz-WebUI setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials web80
else
  echo "Blitz-WebUI setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "d")
if [ ${check} -eq 1 ]; then
  echo "SSH setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials ssh
else
  echo "SSH setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "e")
if [ ${check} -eq 1 ]; then
  echo "RTL setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials rtl
else
  echo "RTL setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "f")
if [ ${check} -eq 1 ]; then
  echo "Thunderhub setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials thunderhub
else
  echo "Thunderhub setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "g")
if [ ${check} -eq 1 ]; then
  echo "LIT setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials lit
else
  echo "LIT setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "h")
if [ ${check} -eq 1 ]; then
  echo "BTCPayServer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials btcpay
else
  echo "BTCPayServer setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "i")
if [ ${check} -eq 1 ]; then
  echo "LNBits setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials lnbits
else
  echo "LNBits setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "j")
if [ ${check} -eq 1 ]; then
  echo "BTC-RPC-Explorer setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials btc-rpc-explorer
else
  echo "BTC-RPC-Explorer setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "k")
if [ ${check} -eq 1 ]; then
  echo "Specter setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials cryptoadvance-specter
else
  echo "Specter setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then
  echo "Mempool setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials mempool
else
  echo "Mempool setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "m")
if [ ${check} -eq 1 ]; then
  echo "ElectRS setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials electrs
else
  echo "ElectRS setting unchanged."
fi

check=$(echo "${CHOICES}" | grep -c "n")
if [ ${check} -eq 1 ]; then
  echo "ElectRS setting CHANGED .."
  ${ONION_SERVICE_SCRIPT} credentials sphinxrelay
else
  echo "ElectRS setting unchanged."
fi