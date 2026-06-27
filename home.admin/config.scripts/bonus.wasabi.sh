#!/bin/bash

# https://github.com/WalletWasabi/WalletWasabi  (WabiSabi coinjoin coordinator backend)
#
# The coordinator-specific changes are merged upstream (master/dev) and ship in the
# next release. Until then, pull master with: bonus.wasabi.sh update commit
#
# REQUIRES bitcoind with: txindex=1, blockfilterindex=1, peerblockfilters=1,
# server=1. The 'on' step ensures these in bitcoin.conf and restarts bitcoind
# (first-time block-filter indexing can take hours).
#
# The .NET SDK channel is read from the project's global.json, so this auto-installs
# the right SDK as the project moves on (8.0 for v2.7.2, 10.0 for v2.8.0).

# Pin the source to the latest official release.
VERSION="v2.8.0"
REPO="WalletWasabi/WalletWasabi"
USERNAME="wasabi"
HOME_DIR="/home/${USERNAME}"
# dedicated clone path - deliberately NOT ${HOME_DIR}/WalletWasabi or
# WalletWasabi-<ver>, which on an existing manual deployment may be a dev tree
# with uncommitted changes. A fresh path means install/update can never
# git-reset/checkout over hand-modified source.
SOURCE_DIR="${HOME_DIR}/wabisabi-coordinator"
PUBLISH_DIR="${SOURCE_DIR}/publish"
CSPROJ="WalletWasabi.Coordinator/WalletWasabi.Coordinator.csproj"
DLL="WalletWasabi.Coordinator.dll"
DATADIR="${HOME_DIR}/.walletwasabi/coordinator"
DOTNET_DIR="${HOME_DIR}/.dotnet"
DOTNET="${DOTNET_DIR}/dotnet"
# fallback .NET channel if global.json cannot be read (real value derived at install)
DOTNET_CHANNEL_FALLBACK="8.0"
# coordinator public API port (Wasabi clients connect here); 5000 is the local-only port
PUBLIC_PORT="37126"
LOCAL_PORT="5000"
SERVICE="wasabicoordinator"

RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/app-data/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Wasabi (WabiSabi) coinjoin coordinator on or off"
  echo "bonus.wasabi.sh [install|uninstall]"
  echo "bonus.wasabi.sh [on|off|status|menu]"
  echo "bonus.wasabi.sh [update|update commit]"
  exit 1
fi

# load raspiblitz config to know network/chain, state & Tor setting
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

# detect install/active state
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
  toraddress=$(sudo cat /mnt/hdd/app-data/tor/${SERVICE}/hostname 2>/dev/null)
  running=$(systemctl is-active ${SERVICE} 2>/dev/null | grep -c "^active$")
  echo "version='${VERSION}'"
  echo "installed='${isActive}'"
  echo "running='${running}'"
  echo "network='${WASABI_NET}'"
  echo "localIP='${localip}'"
  echo "publicPort='${PUBLIC_PORT}'"
  echo "localPort='${LOCAL_PORT}'"
  echo "toraddress='${toraddress}'"
  exit 0
fi

###################
# MENU
###################
if [ "$1" = "menu" ]; then
  if [ ${isActive} -eq 0 ]; then
    echo "# *** WASABI COORDINATOR NOT INSTALLED ***"
    exit 0
  fi
  toraddress=$(sudo cat /mnt/hdd/app-data/tor/${SERVICE}/hostname 2>/dev/null)
  text="Wasabi (WabiSabi) coinjoin coordinator backend.\n
Clients connect to the coordinator API on:
http://${localip}:${PUBLIC_PORT}\n
Config & logs: ${DATADIR}"
  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    text="${text}\n\nTor Hidden Service address:\n${toraddress}"
  fi
  whiptail --title " Wasabi Coordinator " --msgbox "${text}" 16 70
  exit 0
fi

###################
# INSTALL (user + source + .NET + publish)
###################
if [ "$1" = "install" ]; then

  if [ ${isInstalled} -gt 0 ] && [ -d "${PUBLISH_DIR}" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL WASABI COORDINATOR (user, source, .NET, publish) ***"

  # dedicated user
  if [ ${isInstalled} -eq 0 ]; then
    echo "# creating the ${USERNAME} user"
    sudo adduser --system --group --home ${HOME_DIR} ${USERNAME} || exit 1
  fi

  # build dependencies (.NET needs libicu at runtime on ARM)
  sudo apt-get update
  sudo apt-get install -y git curl libicu-dev || exit 1

  # source code
  if [ ! -d "${SOURCE_DIR}" ]; then
    echo "# cloning ${REPO} @ ${VERSION}"
    sudo -u ${USERNAME} git clone https://github.com/${REPO}.git ${SOURCE_DIR} || exit 1
  fi
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  sudo -u ${USERNAME} git checkout --force ${VERSION} || exit 1

  # .NET SDK matching the project's global.json (auto-tracks the .NET 10 release)
  ensure_dotnet_sdk || { echo "result='fail - dotnet sdk install failed'"; exit 1; }

  # publish a self-contained-of-framework build (no rebuild/restore at service start)
  echo "# publishing the coordinator (this can take a while on a Pi)"
  sudo -u ${USERNAME} rm -rf ${PUBLISH_DIR}
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} publish -c Release -o ${PUBLISH_DIR} ${CSPROJ}" || {
    echo "result='fail - dotnet publish failed'"
    exit 1
  }

  echo "# OK - Wasabi coordinator user, source, .NET and publish installed"
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
  echo "# *** UNINSTALL WASABI COORDINATOR ***"
  echo "# NOTE: keeping ${DATADIR} (holds the coordinator wallet xpub & keys)."
  echo "#       Delete it manually only if you are sure you no longer need it."
  # remove source + .NET, keep the data dir (it has the keys)
  sudo rm -rf ${SOURCE_DIR} ${DOTNET_DIR}
  exit 0
fi

###################
# ON
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ ${isActive} -gt 0 ]; then
    echo "# Wasabi coordinator already activated."
    echo "result='OK'"
    exit 0
  fi

  # SAFETY GUARD (first, before any install/build/mutation): do not clobber a
  # pre-existing manual deployment. If a wasabicoordinator.service already exists
  # but does NOT run from our dedicated SOURCE_DIR, abort - it was set up by hand
  # and 'on' would overwrite the unit and patch its live Config.json.
  if [ -f /etc/systemd/system/${SERVICE}.service ] && \
     ! grep -q "${SOURCE_DIR}" /etc/systemd/system/${SERVICE}.service; then
    echo "# ABORT: an existing ${SERVICE}.service was found that does not use ${SOURCE_DIR}." 1>&2
    echo "# This looks like a manual deployment. Refusing to overwrite it." 1>&2
    echo "result='fail - existing manual deployment detected'"
    exit 1
  fi

  # make sure it is installed
  if [ ${isInstalled} -eq 0 ] || [ ! -d "${PUBLISH_DIR}" ]; then
    sudo /home/admin/config.scripts/bonus.wasabi.sh install 1>&2 || exit 1
  fi

  echo "# *** ACTIVATING WASABI COORDINATOR ***"

  # data dir
  sudo -u ${USERNAME} mkdir -p ${DATADIR}

  # --- ensure bitcoind has the indexes/filters the coordinator REQUIRES ---
  # Without these the coordinator cannot function: txindex (look up any tx) and
  # BIP158 compact block filters served to clients (blockfilterindex +
  # peerblockfilters), plus the RPC server. Edit the filter keys first, then let
  # the txindex helper run; restart bitcoind only once.
  echo "# ensuring required ${network}.conf settings"
  btcRestart=0
  for key in server blockfilterindex peerblockfilters; do
    if grep -Eq "^${key}=1" "${BITCOIN_CONF}"; then
      continue
    elif grep -Eq "^${key}=" "${BITCOIN_CONF}"; then
      sudo sed -i "s/^${key}=.*/${key}=1/g" "${BITCOIN_CONF}"
    else
      echo "${key}=1" | sudo tee -a "${BITCOIN_CONF}" >/dev/null
    fi
    echo "# set ${key}=1 in ${network}.conf"
    btcRestart=1
  done
  # txindex via the dedicated helper - it restarts/reindexes itself if it changes
  txindexBefore=$(grep -Eq "^txindex=1" "${BITCOIN_CONF}" && echo 1 || echo 0)
  /home/admin/config.scripts/network.txindex.sh on 1>&2
  # restart bitcoind for the filter changes only if the txindex helper did not already
  if [ ${btcRestart} -eq 1 ] && [ "${txindexBefore}" = "1" ] && systemctl is-active ${BITCOIND_SERVICE} | grep -q "^active"; then
    echo "# restarting ${BITCOIND_SERVICE} to apply block-filter settings"
    echo "# NOTE: first-time block-filter indexing can take hours; the coordinator"
    echo "#       will only serve clients once it has finished."
    sudo systemctl restart ${BITCOIND_SERVICE} 1>&2
  fi

  # generate Config.json on first run, then patch in the bitcoind RPC details.
  # The coordinator writes a default Config.json (incl. a freshly generated
  # CoordinatorExtPubKey) on first start. Run it (bound to localhost only),
  # poll until the file appears, then stop it - no fragile fixed timeout.
  if [ ! -f "${DATADIR}/Config.json" ]; then
    echo "# first run: generating default Config.json ..."
    sudo -u ${USERNAME} bash -c "HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ASPNETCORE_URLS='http://127.0.0.1:${LOCAL_PORT}' ${DOTNET} ${PUBLISH_DIR}/${DLL}" >/dev/null 2>&1 &
    for i in $(seq 1 90); do
      [ -f "${DATADIR}/Config.json" ] && break
      sleep 2
    done
    sudo pkill -u ${USERNAME} -f "${DLL}" 2>/dev/null
    sleep 1
  fi

  # read bitcoind RPC creds from bitcoin.conf and patch Config.json (Python, stdlib)
  if [ -f "${DATADIR}/Config.json" ] && [ -f "${BITCOIN_CONF}" ]; then
    echo "# wiring coordinator to bitcoind RPC"
    sudo python3 - "${DATADIR}/Config.json" "${BITCOIN_CONF}" "${WASABI_NET}" <<'PY'
import json, sys
cfg_path, btc_path, wnet = sys.argv[1], sys.argv[2], sys.argv[3]
conf = {}
for line in open(btc_path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, _, v = line.partition("=")
        conf[k.strip().split(".")[-1]] = v.strip()  # drop main./test. prefixes
user = conf.get("rpcuser", "")
pw = conf.get("rpcpassword", "")
port = conf.get("rpcport", "8332")
with open(cfg_path, encoding="utf-8-sig") as f:
    cfg = json.load(f)
cfg["Network"] = wnet
# URI key prefix: Main->MainNet, TestNet->TestNet, RegTest->RegTest
prefix = "MainNet" if wnet == "Main" else wnet
cfg[f"{prefix}BitcoinRpcUri"] = f"http://127.0.0.1:{port}"
if user and pw:
    cfg["BitcoinRpcConnectionString"] = f"{user}:{pw}"
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
print("# Config.json patched (RPC URI + connection string)")
PY
    sudo chown ${USERNAME}:${USERNAME} "${DATADIR}/Config.json"
    sudo chmod 600 "${DATADIR}/Config.json"
  else
    echo "# WARN: could not patch Config.json automatically - set BitcoinRpcConnectionString manually" 1>&2
  fi

  # systemd service - runs the published DLL directly (no build/restore at start)
  echo "# installing systemd service ${SERVICE}"
  echo "\
[Unit]
Description=Wasabi Coordinator daemon
Requires=${BITCOIND_SERVICE}.service
After=${BITCOIND_SERVICE}.service

[Service]
ExecStart=${DOTNET} ${PUBLISH_DIR}/${DLL}
Environment=HOME=${HOME_DIR}
Environment=DOTNET_ROOT=${DOTNET_DIR}
Environment=\"ASPNETCORE_URLS=http://0.0.0.0:${PUBLIC_PORT};http://127.0.0.1:${LOCAL_PORT}\"
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

  # firewall: open the public coordinator port (5000 stays local-only)
  echo "# *** updating firewall ***" 1>&2
  sudo ufw allow from any to any port ${PUBLIC_PORT} comment 'allow Wasabi coordinator' 1>&2

  # raspiblitz config flag
  /home/admin/config.scripts/blitz.conf.sh set wasabi "on" ${RASPIBLITZ_CONF} 1>&2

  # Tor hidden service (maps onion:80 -> coordinator public port)
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh ${SERVICE} 80 ${PUBLIC_PORT} 1>&2
  fi

  # start if the system is ready
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
  # SAFETY GUARD: only touch a service that this script created (runs from SOURCE_DIR).
  if [ -f /etc/systemd/system/${SERVICE}.service ] && \
     ! grep -q "${SOURCE_DIR}" /etc/systemd/system/${SERVICE}.service; then
    echo "# ABORT: ${SERVICE}.service does not use ${SOURCE_DIR} (manual deployment)." 1>&2
    echo "# Refusing to stop/remove a service this script did not create." 1>&2
    echo "result='fail - existing manual deployment detected'"
    exit 1
  fi

  echo "# *** DEACTIVATE WASABI COORDINATOR ***"

  sudo systemctl stop ${SERVICE} 2>/dev/null
  sudo systemctl disable ${SERVICE} 2>/dev/null
  sudo rm -f /etc/systemd/system/${SERVICE}.service
  sudo systemctl daemon-reload 2>/dev/null

  # close firewall port
  sudo ufw delete allow from any to any port ${PUBLIC_PORT} 1>&2

  # remove Tor hidden service
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off ${SERVICE} 1>&2
  fi

  # raspiblitz config flag
  /home/admin/config.scripts/blitz.conf.sh set wasabi "off" ${RASPIBLITZ_CONF} 1>&2

  echo "# OK - Wasabi coordinator deactivated (source & data kept)"
  echo "result='OK'"
  exit 0
fi

###################
# UPDATE
###################
if [ "$1" = "update" ]; then
  if [ ! -d "${SOURCE_DIR}" ]; then
    echo "# *** WASABI COORDINATOR IS NOT INSTALLED ***"
    exit 1
  fi
  echo "# *** UPDATE WASABI COORDINATOR ***"
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  if [ "$2" = "commit" ]; then
    # track the default branch (master) - has the upstreamed changes before release
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
