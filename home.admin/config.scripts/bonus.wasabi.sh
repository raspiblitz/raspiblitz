#!/bin/bash

# https://github.com/WalletWasabi/WalletWasabi  (WabiSabi coinjoin coordinator backend)
#
# The coinjoin.nl coordinator-specific changes are merged upstream (master/dev) and
# ship in the next release. Until then, pull master with: bonus.wasabi.sh update commit
#
# REQUIRES bitcoind with: txindex=1, blockfilterindex=1, peerblockfilters=1,
# server=1. The 'on' step ensures these in bitcoin.conf and restarts bitcoind
# (first-time block-filter indexing can take hours).

# Pin the source to the latest official release.
VERSION="v2.7.2"
REPO="WalletWasabi/WalletWasabi"
USERNAME="wasabi"
HOME_DIR="/home/${USERNAME}"
# dedicated clone path - deliberately NOT ${HOME_DIR}/WalletWasabi or
# WalletWasabi-<ver>, which on an existing manual deployment may be a dev tree
# with uncommitted changes. A fresh path means install/update can never
# git-reset/checkout over hand-modified source.
SOURCE_DIR="${HOME_DIR}/wabisabi-coordinator"
CSPROJ="WalletWasabi.Coordinator/WalletWasabi.Coordinator.csproj"
DATADIR="${HOME_DIR}/.walletwasabi/coordinator"
DOTNET_DIR="${HOME_DIR}/.dotnet"
DOTNET="${DOTNET_DIR}/dotnet"
# .NET SDK channel; the project's global.json pins the exact feature band.
DOTNET_CHANNEL="8.0"
# coordinator public API port (Wasabi clients connect here); 5000 is the local-only port
PUBLIC_PORT="37126"
LOCAL_PORT="5000"
SERVICE="wasabicoordinator"

RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/app-data/raspiblitz.conf
BITCOIN_CONF=/mnt/hdd/app-data/bitcoin/bitcoin.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Wasabi (WabiSabi) coinjoin coordinator on or off"
  echo "bonus.wasabi.sh [install|uninstall]"
  echo "bonus.wasabi.sh [on|off|status|menu]"
  echo "bonus.wasabi.sh [update|update commit]"
  exit 1
fi

# load raspiblitz config to know network state & Tor setting
source $RASPIBLITZ_INFO 2>/dev/null
source $RASPIBLITZ_CONF 2>/dev/null

# detect install/active state
isInstalled=$(compgen -u | grep -c "^${USERNAME}$")
isActive=$(sudo ls /etc/systemd/system/${SERVICE}.service 2>/dev/null | grep -c "${SERVICE}.service")
localip=$(hostname -I | awk '{print $1}')

###################
# STATUS
###################
if [ "$1" = "status" ]; then
  toraddress=$(sudo cat /mnt/hdd/app-data/tor/${SERVICE}/hostname 2>/dev/null)
  running=$(systemctl is-active ${SERVICE} 2>/dev/null | grep -c "^active$")
  echo "version='${VERSION}'"
  echo "installed='${isActive}'"
  echo "running='${running}'"
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
# INSTALL (user + .NET + source + build)
###################
if [ "$1" = "install" ]; then

  if [ ${isInstalled} -gt 0 ] && [ -d "${SOURCE_DIR}" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL WASABI COORDINATOR (user, .NET, source) ***"

  # dedicated user
  if [ ${isInstalled} -eq 0 ]; then
    echo "# creating the ${USERNAME} user"
    sudo adduser --system --group --home ${HOME_DIR} ${USERNAME} || exit 1
  fi

  # build dependencies (.NET needs libicu at runtime on ARM)
  sudo apt-get install -y git curl libicu-dev || exit 1

  # install the .NET SDK into the user's home (per-user, RaspiBlitz style)
  if ! sudo -u ${USERNAME} ${DOTNET} --version 2>/dev/null | grep -q .; then
    echo "# installing .NET SDK ${DOTNET_CHANNEL} into ${DOTNET_DIR}"
    sudo -u ${USERNAME} bash -c "curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh"
    sudo -u ${USERNAME} bash /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir ${DOTNET_DIR} || exit 1
    rm -f /tmp/dotnet-install.sh
  fi

  # source code
  if [ ! -d "${SOURCE_DIR}" ]; then
    echo "# cloning ${REPO} @ ${VERSION}"
    sudo -u ${USERNAME} git clone https://github.com/${REPO}.git ${SOURCE_DIR} || exit 1
  fi
  cd ${SOURCE_DIR} || exit 1
  sudo -u ${USERNAME} git fetch --tags --force 1>&2
  sudo -u ${USERNAME} git checkout --force ${VERSION} || exit 1

  # build the coordinator
  echo "# building the coordinator (this can take a while on a Pi)"
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} build -c Release ${CSPROJ}" || {
    echo "result='fail - dotnet build failed'"
    exit 1
  }

  echo "# OK - Wasabi coordinator user, .NET and source installed"
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
  if [ ${isInstalled} -eq 0 ] || [ ! -d "${SOURCE_DIR}" ]; then
    sudo /home/admin/config.scripts/bonus.wasabi.sh install 1>&2 || exit 1
  fi

  echo "# *** ACTIVATING WASABI COORDINATOR ***"

  # data dir
  sudo -u ${USERNAME} mkdir -p ${DATADIR}

  # --- ensure bitcoind has the indexes/filters the coordinator REQUIRES ---
  # Without these the coordinator cannot function: txindex (look up any tx) and
  # BIP158 compact block filters served to clients (blockfilterindex +
  # peerblockfilters), plus the RPC server.
  echo "# ensuring required bitcoin.conf settings"
  # txindex via the dedicated RaspiBlitz helper (handles the reindex)
  /home/admin/config.scripts/network.txindex.sh on 1>&2
  btcRestart=0
  for key in server blockfilterindex peerblockfilters; do
    if grep -Eq "^${key}=1" "${BITCOIN_CONF}"; then
      continue
    elif grep -Eq "^${key}=" "${BITCOIN_CONF}"; then
      sudo sed -i "s/^${key}=.*/${key}=1/g" "${BITCOIN_CONF}"
    else
      echo "${key}=1" | sudo tee -a "${BITCOIN_CONF}" >/dev/null
    fi
    echo "# set ${key}=1 in bitcoin.conf"
    btcRestart=1
  done
  if [ ${btcRestart} -eq 1 ] && systemctl is-active bitcoind | grep -q "^active"; then
    echo "# restarting bitcoind to apply block-filter settings"
    echo "# NOTE: first-time block-filter indexing can take hours; the coordinator"
    echo "#       will only serve clients once it has finished."
    sudo systemctl restart bitcoind 1>&2
  fi

  # generate Config.json on first run, then patch in the bitcoind RPC details.
  # The coordinator writes a default Config.json (incl. a freshly generated
  # CoordinatorExtPubKey) the first time it starts, so let it do that, then patch.
  if [ ! -f "${DATADIR}/Config.json" ]; then
    echo "# first run: generating default Config.json ..."
    sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ASPNETCORE_URLS='http://127.0.0.1:${LOCAL_PORT}' timeout 40 ${DOTNET} run -c Release --project ${CSPROJ}" 1>&2 2>/dev/null
  fi

  # read bitcoind RPC creds from bitcoin.conf and patch Config.json (Python, stdlib)
  if [ -f "${DATADIR}/Config.json" ] && [ -f "${BITCOIN_CONF}" ]; then
    echo "# wiring coordinator to bitcoind RPC"
    sudo python3 - "${DATADIR}/Config.json" "${BITCOIN_CONF}" <<'PY'
import json, sys
cfg_path, btc_path = sys.argv[1], sys.argv[2]
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
cfg["Network"] = "Main"
cfg["MainNetBitcoinRpcUri"] = f"http://127.0.0.1:{port}"
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

  # systemd service (mirrors the proven manual unit; builds on first start via 'dotnet run')
  echo "# installing systemd service ${SERVICE}"
  echo "\
[Unit]
Description=Wasabi Coordinator daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
ExecStart=${DOTNET} run -c Release --project ${SOURCE_DIR}/${CSPROJ}
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
    echo "# starting ${SERVICE} (first start compiles, may take minutes)"
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
  sudo -u ${USERNAME} bash -c "cd ${SOURCE_DIR} && HOME=${HOME_DIR} DOTNET_ROOT=${DOTNET_DIR} ${DOTNET} build -c Release ${CSPROJ}" || exit 1
  if [ ${isActive} -gt 0 ]; then
    sudo systemctl restart ${SERVICE} 1>&2
  fi
  echo "# OK - updated and rebuilt"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
