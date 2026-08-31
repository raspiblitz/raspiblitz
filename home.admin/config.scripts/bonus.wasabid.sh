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
# v2.8.0 resets hand-written Config.json keys on load, so behavioral settings are
# passed as WASABI_* env vars (higher precedence) from this root-owned 600 file.
ENV_FILE="/etc/${SERVICE}.env"

RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/app-data/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script for the Wasabi Wallet daemon (headless client + JSON-RPC)"
  echo "bonus.wasabid.sh [install|uninstall]"
  echo "bonus.wasabid.sh [on|off|status|menu]"
  echo "bonus.wasabid.sh [examples]   # print wcli + curl usage cheat sheet"
  echo "bonus.wasabid.sh [update|update <tag>]"
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
    whiptail --title " Wasabi Wallet Daemon " --msgbox "\
Wasabi daemon is not activated.\n
Enable it from the SERVICES menu, or run:
  sudo /home/admin/config.scripts/bonus.wasabid.sh on" 11 72
    exit 0
  fi

  # Live status, guarded with a timeout so the menu never hangs while the daemon
  # is still starting. Query the loopback JSON-RPC directly (auth-less) for clean,
  # parseable output instead of wcli's table formatting.
  _rpc() { timeout 6 curl -s --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"$1\",\"params\":[]}" "http://127.0.0.1:${RPC_PORT}/" 2>/dev/null; }
  if [ "$(systemctl is-active ${SERVICE} 2>/dev/null)" = "active" ]; then
    st=$(_rpc getstatus)
    if echo "${st}" | jq -e '.result' >/dev/null 2>&1; then
      tor=$(echo "${st}" | jq -r '.result.torStatus // "?"')
      net=$(echo "${st}" | jq -r '.result.network // "?"')
      left=$(echo "${st}" | jq -r '.result.filtersLeft // empty')
      [ "${left}" = "0" ] && synced="yes" || synced="syncing"
      statusLine="running | Tor: ${tor} | ${net} | synced: ${synced}"
      cnt=$(_rpc listwallets | jq -r '.result | length' 2>/dev/null)
      case "${cnt}" in ""|null) wallets="?";; 0) wallets="none yet (create one below)";; *) wallets="${cnt}";; esac
    else
      statusLine="running | RPC starting (Tor bootstrapping) - reopen shortly"
      wallets="?"
    fi
  else
    statusLine="STOPPED | start: sudo systemctl start ${SERVICE}"
    wallets="-"
  fi

  whiptail --title " Wasabi Wallet Daemon " --msgbox "\
Status:  ${statusLine}
Wallets: ${wallets}\n
Headless Wasabi wallet, local JSON-RPC on 127.0.0.1:${RPC_PORT} (auth-less).\n
Manage it with the 'wcli' command:
  wcli getstatus                       sync / Tor / node status
  wcli createwallet MyWallet '\"pass\"'
  wcli -wallet=MyWallet getnewaddress \"label\" false
  wcli -wallet=MyWallet startcoinjoin pass true true\n
Full cheat sheet (incl. raw curl):
  sudo /home/admin/config.scripts/bonus.wasabid.sh examples\n
Logs:              sudo journalctl -u ${SERVICE} -f
Settings:          ${ENV_FILE}
Docs:              https://docs.wasabiwallet.io/using-wasabi/RPC.html" 24 78
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
  # RPC endpoint from Config.json itself, so you never type the port.
  cat <<EOF
# ===== Wasabi wallet via wcli (recommended) =====
# wcli is the dev-maintained CLI wrapper. It auto-loads the endpoint from
# ${DATADIR}/Config.json - no need to pass a port (local RPC is auth-less).
#
#   wcli getstatus                  # sync / Tor / node status
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
# Local RPC is auth-less (127.0.0.1 only), so no credentials are needed:
#   curl -s --data-binary \\
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

  # Behavioral settings go through WASABI_* env vars, NOT Config.json: v2.8.0 runs
  # a config migration on load that resets hand-written keys (JsonRpcServerEnabled,
  # UseBitcoinRpc, Network, ...) back to defaults. Env vars outrank the config file
  # and survive that rewrite. Local JSON-RPC stays auth-less (127.0.0.1 only, no
  # firewall port) - that is upstream's own localhost RPC model.
  echo "# writing ${ENV_FILE} (RPC enable + network + local bitcoind wiring)"
  sudo python3 - "${ENV_FILE}" "${WASABI_NET}" "${BITCOIN_CONF}" <<'PY'
import sys, os
env_path, wnet, btc_path = sys.argv[1:4]
lines = [
    "WASABI_JSONRPCSERVERENABLED=true",
    f"WASABI_NETWORK={wnet}",
]
# wire the client to the local bitcoind via RPC (trustless, uses the user's node)
# bitcoin.conf is network-scoped (main.rpcport=8332, test.rpcport=18332, ...), so
# read the value for THIS network's prefix - never collapse them (a mainnet node
# must not pick up test.rpcport=18332).
NETMAP = {"Main": ("main", "8332"), "TestNet": ("test", "18332"),
          "RegTest": ("regtest", "18443"), "Signet": ("signet", "38332")}
cprefix, default_port = NETMAP.get(wnet, ("main", "8332"))
def conf_get(key):
    scoped = glob = None
    for line in open(btc_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k == f"{cprefix}.{key}":
            scoped = v
        elif k == key:
            glob = v
    return scoped if scoped is not None else glob
if os.path.exists(btc_path):
    user = conf_get("rpcuser") or ""
    pwd = conf_get("rpcpassword") or ""
    rpcport = conf_get("rpcport") or default_port
    if user and pwd:
        # the daemon decides "RPC configured" solely on BitcoinRpcUri being set,
        # and that property is fed by the switch named BitcoinRpcEndPoint (there is
        # no UseBitcoinRpc switch). A loopback URI is used directly (not via Tor).
        lines += [
            f"WASABI_BITCOINRPCCREDENTIALSTRING={user}:{pwd}",
            f"WASABI_BITCOINRPCENDPOINT=http://127.0.0.1:{rpcport}",
        ]
with open(env_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
  sudo chown root:root "${ENV_FILE}"
  sudo chmod 600 "${ENV_FILE}"

  # The daemon writes its own Config.json (default port ${RPC_PORT}) on first run;
  # pre-seed a minimal one so 'wcli' has an endpoint to read immediately. The daemon
  # preserves the prefix and fills the rest; auth stays empty so wcli needs no creds.
  if [ ! -f "${DATADIR}/Config.json" ]; then
    echo "{\"JsonRpcServerPrefixes\": [\"http://127.0.0.1:${RPC_PORT}/\"]}" \
      | sudo -u ${USERNAME} tee "${DATADIR}/Config.json" >/dev/null
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
EnvironmentFile=${ENV_FILE}
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
  # user so it reads that user's Config.json for the endpoint; RPC is auth-less)
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
  sudo rm -f ${ENV_FILE}
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
  # 'update' rebuilds the pinned VERSION; 'update <tag>' targets a specific upstream
  # release tag (e.g. v2.8.1) for operators who want a newer build before the script
  # pin is bumped. Only build a version you trust - it compiles upstream source as-is.
  TARGET="${2:-$VERSION}"
  [ "${TARGET}" != "${VERSION}" ] && echo "# NOTE: building ${TARGET}, not the pinned ${VERSION}" 1>&2
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  sudo -u ${USERNAME} git checkout --force "${TARGET}" || exit 1
  # the new checkout may require a newer .NET SDK (e.g. 10.0) - ensure it
  ensure_dotnet_sdk || exit 1
  sudo -u ${USERNAME} rm -rf ${PUBLISH_DIR}
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} publish -c Release -o ${PUBLISH_DIR} ${CSPROJ}" || exit 1
  # publish drops the execute bit on bundled native binaries (Tor, hwi) - restore it
  sudo find ${PUBLISH_DIR}/BundledApps/Binaries -type f \( -name tor -o -name hwi \) -exec chmod +x {} \;
  if [ ${isActive} -gt 0 ]; then
    sudo systemctl restart ${SERVICE} 1>&2
  fi
  echo "# OK - updated and re-published"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
