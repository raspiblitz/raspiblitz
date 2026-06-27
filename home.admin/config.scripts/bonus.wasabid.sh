#!/bin/bash

# https://github.com/WalletWasabi/WalletWasabi  (WalletWasabi.Daemon - headless client wallet)
#
# Headless Wasabi wallet daemon with a local JSON-RPC interface. Manage wallets
# from the command line via the wcli script or any RPC client. This is the
# client wallet (for end users) - NOT the coinjoin coordinator (that is the
# advanced-only bonus.wasabi.sh).
#
# The .NET SDK channel is read from the project's global.json, so this auto-installs
# the right SDK as the project moves on (8.0 for v2.7.2, 10.0 for v2.8.0).

VERSION="v2.8.0"
REPO="WalletWasabi/WalletWasabi"
USERNAME="wasabid"
HOME_DIR="/home/${USERNAME}"
# dedicated clone path (isolated from any manual deployment / dev tree)
SOURCE_DIR="${HOME_DIR}/wabisabi-client"
PUBLISH_DIR="${SOURCE_DIR}/publish"
CSPROJ="WalletWasabi.Daemon/WalletWasabi.Daemon.csproj"
DLL="WalletWasabi.Daemon.dll"
DATADIR="${HOME_DIR}/.walletwasabi/client"
DOTNET_DIR="${HOME_DIR}/.dotnet"
DOTNET="${DOTNET_DIR}/dotnet"
DOTNET_CHANNEL_FALLBACK="8.0"
# local-only JSON-RPC (Wasabi default port); never exposed to the network
RPC_PORT="37128"
SERVICE="wasabid"

RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/app-data/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script for the Wasabi Wallet daemon (headless client + JSON-RPC)"
  echo "bonus.wasabid.sh [install|uninstall]"
  echo "bonus.wasabid.sh [on|off|status|menu]"
  echo "bonus.wasabid.sh [examples]   # print wcli + curl usage cheat sheet"
  echo "bonus.wasabid.sh [update|update commit]"
  exit 1
fi

source $RASPIBLITZ_INFO 2>/dev/null
source $RASPIBLITZ_CONF 2>/dev/null

# network awareness (RaspiBlitz: network=bitcoin, chain=main|test|sig|reg)
network="${network:-bitcoin}"
chain="${chain:-main}"
BITCOIN_CONF="/mnt/hdd/app-data/${network}/${network}.conf"
BITCOIND_SERVICE="${network}d"
case "${chain}" in
  main) WASABI_NET="Main" ;;
  test) WASABI_NET="TestNet" ;;
  reg)  WASABI_NET="RegTest" ;;
  *)    WASABI_NET="Main" ;;
esac

isInstalled=$(compgen -u | grep -c "^${USERNAME}$")
isActive=$(sudo ls /etc/systemd/system/${SERVICE}.service 2>/dev/null | grep -c "${SERVICE}.service")
localip=$(hostname -I | awk '{print $1}')

# helper: derive + ensure the .NET SDK the project's global.json asks for
ensure_dotnet_sdk() {
  local channel
  channel=$(grep -oE '"version"[^"]*"[0-9]+\.[0-9]+' "${SOURCE_DIR}/global.json" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+$' | head -1)
  [ -z "${channel}" ] && channel="${DOTNET_CHANNEL_FALLBACK}"
  echo "# project needs .NET SDK channel ${channel} (from global.json)"
  if ! sudo -u ${USERNAME} bash -c "DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} --list-sdks 2>/dev/null" \
       | grep -q "^${channel}\."; then
    echo "# installing .NET SDK ${channel} into ${DOTNET_DIR}"
    sudo -u ${USERNAME} bash -c "curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh" || return 1
    sudo -u ${USERNAME} bash /tmp/dotnet-install.sh --channel ${channel} --install-dir ${DOTNET_DIR} || return 1
    rm -f /tmp/dotnet-install.sh
  else
    echo "# .NET SDK ${channel} already present"
  fi
}

###################
# STATUS
###################
if [ "$1" = "status" ]; then
  running=$(systemctl is-active ${SERVICE} 2>/dev/null | grep -c "^active$")
  echo "version='${VERSION}'"
  echo "installed='${isActive}'"
  echo "running='${running}'"
  echo "network='${WASABI_NET}'"
  echo "localIP='${localip}'"
  echo "rpcPort='${RPC_PORT}'"
  echo "rpcBind='127.0.0.1'"
  echo "dataDir='${DATADIR}'"
  exit 0
fi

###################
# MENU
###################
if [ "$1" = "menu" ]; then
  if [ ${isActive} -eq 0 ]; then
    echo "# *** WASABI DAEMON NOT INSTALLED ***"
    exit 0
  fi
  whiptail --title " Wasabi Wallet Daemon " --msgbox "\
Headless Wasabi wallet with a local JSON-RPC interface.\n
JSON-RPC endpoint (localhost only):
  http://127.0.0.1:${RPC_PORT}/           (global)
  http://127.0.0.1:${RPC_PORT}/WalletName (per wallet)\n
Easiest interaction is the dev-maintained 'wcli' command (installed):
  wcli help                         list all methods
  wcli createwallet MyWallet '\"pass\"'
  wcli -wallet=MyWallet getnewaddress \"label\" false
  wcli -wallet=MyWallet startcoinjoin pass true true
It auto-loads the RPC endpoint + credentials from Config.json.\n
For a fuller cheat sheet (incl. raw curl):
  sudo /home/admin/config.scripts/bonus.wasabid.sh examples\n
RPC creds live in: ${DATADIR}/Config.json
Docs: https://docs.wasabiwallet.io/using-wasabi/RPC.html
" 22 76
  exit 0
fi

###################
# EXAMPLES (teach the RPC calls)
###################
if [ "$1" = "examples" ] || [ "$1" = "rpc" ]; then
  if [ ! -f "${DATADIR}/Config.json" ]; then
    echo "# Wasabi daemon is not configured yet - run 'on' first."
    exit 1
  fi
  # The 'wcli' wrapper (installed by 'on') is the dev-maintained CLI. It reads the
  # RPC endpoint + credentials from Config.json itself, so you never type them.
  cat <<EOF
# ===== Wasabi wallet via wcli (recommended) =====
# wcli is the dev-maintained CLI wrapper. It auto-loads the endpoint and the RPC
# credentials from ${DATADIR}/Config.json - no need to pass a port or password.
#
#   wcli help                       # authoritative list of all methods
#   wcli <method> [params...]       # global call
#   wcli -wallet=<name> <method> ..  # call against a specific wallet
#
# Note on quoting: wcli auto-quotes the FIRST parameter as a string; pass any
# further STRING parameters pre-quoted as '"..."' (numbers/bools stay bare).

# 1) Create a new wallet (returns the recovery mnemonic - write it down!)
wcli createwallet MyWallet '"MyPassphrase"'

# 2) Recover a wallet from a BIP39 mnemonic
wcli recoverwallet MyWallet '"word1 word2 ... word12"' '"MyPassphrase"'

# 3) Get a new receive address  (label, isTaproot)
wcli -wallet=MyWallet getnewaddress "my label" false

# 4) Start coinjoin  (passphrase, stopWhenAllMixed, overridePlebStop)
wcli -wallet=MyWallet startcoinjoin MyPassphrase true true

# 5) Pay in coinjoin  (destinationAddress, amountInSats)
wcli -wallet=MyWallet payincoinjoin "bc1q..." 100000

# List wallets / wallet info
wcli listwallets
wcli -wallet=MyWallet getwalletinfo

# ----- raw curl equivalent (if you prefer) -----
# Add basic auth from Config.json: -u <JsonRpcUser>:<JsonRpcPassword>
#   curl -s -u USER:PASS --data-binary \\
#     '{"jsonrpc":"2.0","id":"1","method":"getnewaddress","params":["label",false]}' \\
#     http://127.0.0.1:${RPC_PORT}/MyWallet | jq
#
# Full method reference: https://docs.wasabiwallet.io/using-wasabi/RPC.html
EOF
  exit 0
fi

###################
# INSTALL
###################
if [ "$1" = "install" ]; then

  if [ ${isInstalled} -gt 0 ] && [ -d "${PUBLISH_DIR}" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL WASABI DAEMON (user, source, .NET, publish) ***"

  if [ ${isInstalled} -eq 0 ]; then
    echo "# creating the ${USERNAME} user"
    sudo adduser --system --group --home ${HOME_DIR} ${USERNAME} || exit 1
  fi

  sudo apt-get update
  sudo apt-get install -y git curl libicu-dev jq || exit 1

  if [ ! -d "${SOURCE_DIR}" ]; then
    echo "# cloning ${REPO} @ ${VERSION}"
    sudo -u ${USERNAME} git clone https://github.com/${REPO}.git ${SOURCE_DIR} || exit 1
  fi
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  sudo -u ${USERNAME} git checkout --force ${VERSION} || exit 1

  # .NET SDK matching the project's global.json (auto-tracks the .NET 10 release)
  ensure_dotnet_sdk || { echo "result='fail - dotnet sdk install failed'"; exit 1; }

  echo "# publishing the daemon (this can take a while on a Pi)"
  sudo -u ${USERNAME} rm -rf ${PUBLISH_DIR}
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} publish -c Release -o ${PUBLISH_DIR} ${CSPROJ}" || {
    echo "result='fail - dotnet publish failed'"
    exit 1
  }

  # dotnet publish drops the execute bit on the bundled native binaries (Tor, hwi),
  # so the daemon aborts at startup with "Permission denied" trying to launch Tor.
  # Restore +x on them across whatever arch dirs were published.
  echo "# restoring execute bit on bundled native binaries (Tor, hwi)"
  sudo find ${PUBLISH_DIR}/BundledApps/Binaries -type f \( -name tor -o -name hwi \) -exec chmod +x {} \;

  echo "# OK - Wasabi daemon user, source, .NET and publish installed"
  exit 0
fi

###################
# UNINSTALL
###################
if [ "$1" = "uninstall" ]; then
  if [ ${isActive} -gt 0 ]; then
    echo "result='still in use - switch off first'"
    exit 1
  fi
  echo "# *** UNINSTALL WASABI DAEMON ***"
  echo "# NOTE: keeping ${DATADIR} (holds your wallets). Delete manually if sure."
  sudo rm -rf ${SOURCE_DIR} ${DOTNET_DIR}
  exit 0
fi

###################
# ON
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ ${isActive} -gt 0 ]; then
    echo "# Wasabi daemon already activated."
    echo "result='OK'"
    exit 0
  fi

  if [ ${isInstalled} -eq 0 ] || [ ! -d "${PUBLISH_DIR}" ]; then
    sudo /home/admin/config.scripts/bonus.wasabid.sh install 1>&2 || exit 1
  fi

  echo "# *** ACTIVATING WASABI DAEMON ***"

  sudo -u ${USERNAME} mkdir -p ${DATADIR}

  # write Config.json on first run: local JSON-RPC + wire to the local bitcoind.
  # The daemon fills any missing keys with its own defaults on start.
  if [ ! -f "${DATADIR}/Config.json" ]; then
    echo "# generating Config.json (local JSON-RPC + local bitcoind RPC)"
    RPCPASS=$(openssl rand -hex 24)
    sudo python3 - "${DATADIR}/Config.json" "${RPC_PORT}" "${RPCPASS}" "${WASABI_NET}" "${BITCOIN_CONF}" <<'PY'
import json, sys, os
path, port, pw, wnet, btc_path = sys.argv[1:6]
cfg = {
    "Network": wnet,
    "UseTor": "Enabled",
    "JsonRpcServerEnabled": True,
    "JsonRpcUser": "wasabi",
    "JsonRpcPassword": pw,
    "JsonRpcServerPrefixes": [f"http://127.0.0.1:{port}/"],
}
# wire the client to the local bitcoind via RPC (trustless, uses the user's node)
if os.path.exists(btc_path):
    conf = {}
    for line in open(btc_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            conf[k.strip().split(".")[-1]] = v.strip()  # drop main./test. prefixes
    user = conf.get("rpcuser", "")
    pwd = conf.get("rpcpassword", "")
    rpcport = conf.get("rpcport", "8332")
    if user and pwd:
        cfg["UseBitcoinRpc"] = True
        cfg["BitcoinRpcCredentialString"] = f"{user}:{pwd}"
        cfg["BitcoinRpcUri"] = f"http://127.0.0.1:{rpcport}"
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PY
    sudo chown -R ${USERNAME}:${USERNAME} "${HOME_DIR}/.walletwasabi"
    sudo chmod 600 "${DATADIR}/Config.json"
  fi

  echo "# installing systemd service ${SERVICE}"
  echo "\
[Unit]
Description=Wasabi Wallet daemon (headless client + JSON-RPC)
Wants=${BITCOIND_SERVICE}.service
After=${BITCOIND_SERVICE}.service

[Service]
ExecStart=${DOTNET} ${PUBLISH_DIR}/${DLL} --datadir=${DATADIR}
Environment=HOME=${HOME_DIR}
Environment=DOTNET_ROOT=${DOTNET_DIR}
User=${USERNAME}
Group=${USERNAME}
Type=simple
Restart=always
RestartSec=10

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${SERVICE}.service 1>&2
  sudo systemctl daemon-reload 1>&2
  sudo systemctl enable ${SERVICE} 1>&2

  # install the dev-maintained 'wcli' as a system command (runs as the daemon
  # user so it reads that user's Config.json for endpoint + credentials)
  echo "# installing the wcli command"
  printf '#!/bin/bash\nsudo -u %s HOME=%s bash %s/Contrib/CLI/wcli.sh "$@"\n' \
    "${USERNAME}" "${HOME_DIR}" "${SOURCE_DIR}" | sudo tee /usr/local/bin/wcli >/dev/null
  sudo chmod +x /usr/local/bin/wcli

  # local-only RPC: no firewall port opened on purpose

  /home/admin/config.scripts/blitz.conf.sh set wasabid "on" ${RASPIBLITZ_CONF} 1>&2

  source $RASPIBLITZ_INFO 2>/dev/null
  if [ "${state}" = "ready" ]; then
    echo "# starting ${SERVICE}"
    sudo systemctl start ${SERVICE} 1>&2
  else
    echo "# enabled; start manually with: sudo systemctl start ${SERVICE}"
  fi

  echo "result='OK'"
  exit 0
fi

###################
# OFF
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# *** DEACTIVATE WASABI DAEMON ***"

  sudo systemctl stop ${SERVICE} 2>/dev/null
  sudo systemctl disable ${SERVICE} 2>/dev/null
  sudo rm -f /etc/systemd/system/${SERVICE}.service
  sudo systemctl daemon-reload 2>/dev/null

  # remove the wcli command
  sudo rm -f /usr/local/bin/wcli

  /home/admin/config.scripts/blitz.conf.sh set wasabid "off" ${RASPIBLITZ_CONF} 1>&2

  echo "# OK - Wasabi daemon deactivated (source & wallets kept)"
  echo "result='OK'"
  exit 0
fi

###################
# UPDATE
###################
if [ "$1" = "update" ]; then
  if [ ! -d "${SOURCE_DIR}" ]; then
    echo "# *** WASABI DAEMON IS NOT INSTALLED ***"
    exit 1
  fi
  echo "# *** UPDATE WASABI DAEMON ***"
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  if [ "$2" = "commit" ]; then
    sudo -u ${USERNAME} git checkout --force master 1>&2
    sudo -u ${USERNAME} git pull 1>&2
  else
    sudo -u ${USERNAME} git checkout --force ${VERSION} || exit 1
  fi
  # the new checkout may require a newer .NET SDK (e.g. 10.0) - ensure it
  ensure_dotnet_sdk || exit 1
  sudo -u ${USERNAME} rm -rf ${PUBLISH_DIR}
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} publish -c Release -o ${PUBLISH_DIR} ${CSPROJ}" || exit 1
  if [ ${isActive} -gt 0 ]; then
    sudo systemctl restart ${SERVICE} 1>&2
  fi
  echo "# OK - updated and re-published"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
