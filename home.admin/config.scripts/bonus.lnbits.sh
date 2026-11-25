#!/bin/bash

# https://github.com/lnbits/lnbits

# https://github.com/lnbits/lnbits/releases
tag="v1.7.1"
VERSION="${tag}"
# LNbits does not sign tags or commits: the code of ${VERSION} has to be this commit
tagCommit="4fa70f338d274e14fc82746a83fba5c2c658211f"

# uv installs the dependencies from the uv.lock of the LNbits release
# (poetry is legacy upstream and cannot install LNbits on Python 3.13)
# https://pypi.org/project/uv/#files
uvVersion="0.13.5"
# sha256 of the Linux wheels: manylinux_2_17_aarch64, manylinux_2_28_aarch64, manylinux_2_17_x86_64
uvChecksums="2386c2dc9b59fc1d39b1c500e4319d71d3268232eb3b38e29cd6775d6269e8d4
91e58e304b63b6c91bac5561459ab0c3ea24f17bc01ea9359d69fed72142978f
fa8d26e08e34c29c0c4e820cf3181757086d547240b4f4d31ff1d8bd810ca946"

lnbitsCodeDir="/home/lnbits/lnbits"
# virtual environment of the lnbits user that only contains uv
lnbitsUvDir="/home/lnbits/.uv"
# LNbits runs from the virtual environment that uv creates in the code directory
lnbitsBin="${lnbitsCodeDir}/.venv/bin/lnbits"
lnbitsExecStart="${lnbitsBin} --port 5000 --host 0.0.0.0"

# install the pinned uv for the lnbits user (no system-wide pip install needed)
function installUv() {
  local installedUv checksum requirement
  installedUv=$(sudo -u lnbits ${lnbitsUvDir}/bin/uv --version 2>/dev/null | cut -d" " -f2)
  if [ "${installedUv}" = "${uvVersion}" ]; then
    echo "# uv ${uvVersion} is already installed"
    return 0
  fi

  echo "# install uv ${uvVersion}"
  sudo -u lnbits rm -rf ${lnbitsUvDir}
  sudo -u lnbits python3 -m venv ${lnbitsUvDir} || return 1
  # pip only accepts a wheel that matches one of the pinned checksums
  requirement="uv==${uvVersion}"
  for checksum in ${uvChecksums}; do
    requirement="${requirement} --hash=sha256:${checksum}"
  done
  echo "${requirement}" | sudo -u lnbits tee ${lnbitsUvDir}/requirements.txt >/dev/null || return 1
  if ! sudo -u lnbits ${lnbitsUvDir}/bin/pip install --disable-pip-version-check \
    --require-hashes --only-binary :all: -r ${lnbitsUvDir}/requirements.txt; then
    echo "# FAIL: could not install uv ${uvVersion}"
    # dont keep a half installed uv
    sudo -u lnbits rm -rf ${lnbitsUvDir}
    return 1
  fi
}

# install the dependencies of the checked out LNbits version
function installDependencies() {
  installUv || return 1
  echo "# installing application dependencies"
  # --frozen: exactly the versions from the uv.lock of the release
  # --no-dev: without the development tools
  # --no-python-downloads: only use the Python of the system
  # (no extras: the 'migration' extra would make tools/conv.py work, see the migrate command)
  if ! sudo -u lnbits ${lnbitsUvDir}/bin/uv sync --frozen --no-dev --no-python-downloads --directory "$lnbitsCodeDir"; then
    echo "# FAIL: uv sync failed (see above)"
    return 1
  fi
  if ! sudo -u lnbits test -x ${lnbitsBin}; then
    echo "# FAIL: ${lnbitsBin} is missing after uv sync"
    return 1
  fi
  # free the space of the download cache (the installed files stay in the venv)
  sudo -u lnbits ${lnbitsUvDir}/bin/uv cache clean >/dev/null 2>&1
  # remove the virtual environment of poetry (used up to LNbits v1.2.1)
  sudo -u lnbits rm -rf /home/lnbits/.cache/pypoetry
  return 0
}

# check that a git revision of the code directory is the pinned commit of ${VERSION}
function verifyCommit() {
  local found
  found=$(sudo -u lnbits git -C ${lnbitsCodeDir} rev-parse --verify "${1}^{commit}" 2>/dev/null)
  if [ "${found}" != "${tagCommit}" ]; then
    echo "# FAIL: ${1} is the commit '${found}' - ${VERSION} is pinned to ${tagCommit}"
    return 1
  fi
  echo "# OK: ${1} is the pinned commit ${tagCommit}"
}

# installs made with LNbits up to v1.2.1 start with 'poetry run lnbits'
function supportedLnbitsUnit() {
  local configured effective host args cmd
  configured=$(sudo sed -n 's/^ExecStart=//p' /etc/systemd/system/lnbits.service) || return 1
  effective=$(systemctl show lnbits --property=ExecStart --value) || return 1
  [ "$(systemctl show lnbits --property=User --value)" = lnbits ] || return 1
  for host in 127.0.0.1 0.0.0.0; do
    args="--port 5000 --host $host"
    case "$configured" in
      "$lnbitsBin $args") cmd="$configured" ;;
      "/bin/sh -c 'cd $lnbitsCodeDir && poetry run lnbits $args'") cmd="/bin/sh -c cd $lnbitsCodeDir && poetry run lnbits $args" ;;
      *) continue ;;
    esac
    # Compare the effective command too: a drop-in can replace the one on disk.
    [[ "$effective" == "{ path=${cmd%% *} ; argv[]=$cmd ; ignore_errors=no ;"* ]] && return 0
  done
  return 1
}

function setServiceExecStart() {
  if sudo test -f /etc/systemd/system/lnbits.service; then
    supportedLnbitsUnit || return 1
    # Keep the configured bind address, including a loopback-only installation.
    sudo sed -i "s|^ExecStart=/bin/sh -c 'cd /home/lnbits/lnbits && poetry run lnbits \(--port 5000 --host [[:alnum:].:-]\+\)'$|ExecStart=${lnbitsBin} \1|" /etc/systemd/system/lnbits.service || return 1
    sudo systemctl daemon-reload
  fi
}

# A failed update must stay stopped across a reboot. Keep existing enablement
# and remember whether a successful retry should bring this service back.
updateDropIn=/etc/systemd/system/lnbits.service.d/50-raspiblitz-update.conf
trialStart=/run/raspiblitz-lnbits/start-once

function lockLnbitsData() {
  local dir=/run/raspiblitz-lnbits
  sudo install -d -o root -g admin -m 0751 "$dir" || return 1
  # Nested calls (on -> install/switch, for example) inherit the same lock.
  if ! [ "/proc/$$/fd/9" -ef "$dir" ]; then exec 9<"$dir" || return 1; fi
  flock -n 9
}

function holdLnbitsService() {
  # The service account can run the probe even when the admin home is private.
  sudo install -o root -g root -m 0644 /home/admin/config.scripts/bonus.lnbits.sh "${trialStart%/*}/check-start" || return 1
  if ! sudo test -f "$updateDropIn"; then
    sudo mkdir -p "${updateDropIn%/*}" || return 1
    {
      printf '# resume=%s\n# operation=%s\n' "$resumeService" "${holdOperation:-update}"
      if [ "${previousActive:-0}" = 1 ] && [ "${previousCommit:-}" = "$tagCommit" ]; then
        echo "# restartable=$tagCommit"
      fi
      printf '[Unit]\nConditionPathExists=%s\n[Service]\n' "$trialStart"
      printf 'ExecStartPre=+/usr/bin/rm -f -- %s\n' "$trialStart"
      printf 'TimeoutStartSec=6min\nExecStartPost=/bin/bash %s/check-start check-start\n' "${trialStart%/*}"
    } |
      sudo tee "$updateDropIn.new" >/dev/null &&
      sudo chmod 644 "$updateDropIn.new" &&
      sudo mv -T -- "$updateDropIn.new" "$updateDropIn" || return 1
  fi
  sudo rm -f -- "$trialStart" && sudo systemctl daemon-reload && sudo systemctl stop lnbits &&
    sudo systemctl reset-failed lnbits &&
    [ "$(systemctl show lnbits --property=ActiveState --value)" = inactive ]
}

function releaseLnbitsService() {
  sudo rm -f -- "$updateDropIn" "$updateDropIn.new" "$trialStart" "${trialStart%/*}/check-start" && sudo systemctl daemon-reload
}

function lnbitsHttpReady() {
  local response
  response=$(curl --noproxy '*' --fail --silent --max-time 4 --write-out '\n%{http_code}' \
    http://127.0.0.1:5000/api/v1/health) || return 1
  [ "${response##*$'\n'}" = 200 ] &&
    jq -e 'type == "object" and (.server_time | type == "number") and (.up_time != null)' \
      <<<"${response%$'\n'*}" >/dev/null
}

function lnbitsHealthy() {
  systemctl is-active --quiet lnbits && lnbitsHttpReady
}

function startCheckedLnbits() {
  local started=0
  # Only this live operation permits a single start. systemd consumes the
  # permit and verifies HTTP itself even if the menu or updater disappears.
  sudo ln -sT "/proc/$$/fd/9" "$trialStart" || return 1
  if sudo systemctl start lnbits; then started=1; fi
  sudo rm -f -- "$trialStart" || return 1
  [ "$started" = 1 ] && lnbitsHealthy && releaseLnbitsService
}

# Only releases verified from the publisher and actually running at entry are
# eligible for the operator's explicit restart before any checkout/migration.
function previousLnbitsIsSafe() {
  [ "$previousActive" = 1 ] && [ "$beforeCheckout" = 1 ] || return 1
  # v1.7.1 is itself a mandatory security patch for v1.7.0.
  [ "$previousCommit" = "$tagCommit" ] || return 1
  local actual commandLine head changes
  commandLine=$(systemctl show lnbits --property=ExecStart --value) || return 1
  [[ "$commandLine" == *"path=$lnbitsBin ; argv[]=$lnbitsBin "* ]] || return 1
  actual=$(sudo -u lnbits "$lnbitsCodeDir/.venv/bin/python" -I -c 'from importlib.metadata import version; print(version("lnbits"))') || return 1
  [ "$actual" = "${tag#v}" ] || return 1
  head=$(sudo -u lnbits git -C "$lnbitsCodeDir" rev-parse HEAD) &&
    [ "$head" = "$previousCommit" ] &&
    changes=$(sudo -u lnbits git -C "$lnbitsCodeDir" status --porcelain) && [ -z "$changes" ]
}

function failLnbitsUpdate() {
  local reason=$1 choice state
  echo "# FAIL: $reason" >&2
  echo "error='$reason'"
  [ "$updateMenu" = 1 ] || exit 1
  state=$(systemctl show lnbits --property=ActiveState --value 2>/dev/null) || state=unknown
  local choices=(BACK "Return to the menu" RETRY "Retry the update")
  if previousLnbitsIsSafe; then choices+=(START "Start the previous verified version"); fi
  choice=$(whiptail --title "LNbits update failed" --menu "$reason. Service: ${state:-unknown}." \
    16 72 3 "${choices[@]}" 3>&1 1>&2 2>&3) || exit 1
  case "$choice" in
    RETRY) exit 20 ;; # the menu invokes a new attempt after releasing the lock
    START)
      if previousLnbitsIsSafe && startCheckedLnbits; then
        whiptail --title "LNbits" --msgbox "The previous version is running. The update is still pending." 9 66
      else
        if holdLnbitsService; then state=stopped; else state="unknown; check systemctl status lnbits"; fi
        whiptail --title "LNbits" --msgbox "Could not restart the previous version. Service: $state." 10 68
      fi ;;
  esac
  exit 1
}

# what to do after an update from a LNbits version before v1.7.0
# https://news.lnbits.com/news/lnbits-1-7-0-security-update
function securityNotice() {
  echo
  echo "#######################################################################"
  echo "# IMPORTANT: LNbits before v1.7.0 has a critical vulnerability."
  echo "# The update does not lock out an attacker who already copied credentials:"
  echo "# - reset all wallet keys in LNbits as Super User:"
  echo "#   Settings -> Users -> Reset Wallet Keys"
  echo "#   (needs the Admin UI: LNbits menu > OPTIONS > Activate 'Admin UI')"
  echo "# - renew the connections of apps and extensions"
  echo "#   (NWC, LNDHub, Bolt Cards, TPoS, ...) with the new keys"
  echo "# - replace the credentials of the funding source,"
  echo "#   with LND these are the macaroons stored in the LNbits config"
  echo "# - replace all other secrets stored in the LNbits settings"
  echo "# - if you suspect a compromise: keep the logs and set up LNbits on a"
  echo "#   fresh system, an update cannot remove access an attacker already has"
  echo "# https://news.lnbits.com/news/lnbits-1-7-0-security-update"
  echo "#"
  echo "# The login in the browser now needs HTTPS (port 5001) or the Tor address"
  echo "# in the Tor Browser, plain HTTP on port 5000 does not keep the session."
  echo "#######################################################################"
}

# command info
if [ "${1:-}" = check-start ]; then
  deadline=$((SECONDS + 300))
  until lnbitsHttpReady; do
    (( SECONDS < deadline )) || exit 1
    sleep 1
  done
  exit 0
fi

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch LNbits on or off."
  echo "Installs the version ${VERSION} by default."
  echo "Usage:"
  echo "bonus.lnbits.sh [install|uninstall] [?GITHUBUSER] [?BRANCH|?TAG]"
  echo "bonus.lnbits.sh update"
  echo "bonus.lnbits.sh on [lnd|tlnd|slnd|cl|tcl|scl]"
  echo "bonus.lnbits.sh switch [lnd|tlnd|slnd|cl|tcl|scl]"
  echo "bonus.lnbits.sh off <--keep-data|--delete-data>"
  echo "bonus.lnbits.sh status"
  echo "bonus.lnbits.sh menu"
  echo "bonus.lnbits.sh prestart"
  echo "bonus.lnbits.sh repo [githubuser] [branch]"
  echo "bonus.lnbits.sh sync"
  echo "bonus.lnbits.sh backup"
  echo "bonus.lnbits.sh restore [?FILE]"
  echo "bonus.lnbits.sh migrate"
  exit 1
fi

echo "# Running: 'bonus.lnbits.sh $*'"
source /mnt/hdd/app-data/raspiblitz.conf

lnbitsDataDir="/mnt/hdd/app-data/LNBits/data"
lnbitsConfig="${lnbitsDataDir}/.env"

case "$1" in
  update|on|1|off|0|install|uninstall|backup|restore|switch|migrate|sync|repo)
    if ! lockLnbitsData; then
      beforeCheckout=0; previousActive=0; updateMenu=0
      if [ "$1" = update ] && [ "${2:-}" = --menu ]; then updateMenu=1; fi
      failLnbitsUpdate "Another LNbits operation is in progress or the lock is unavailable"
    fi ;;
esac

function postgresConfig() {

  sudo /home/admin/config.scripts/bonus.postgresql.sh on || exit 1
  echo "# Generate the database lnbits_db"

  # migrate clean up
  source <(/home/admin/_cache.sh get LNBitsMigrate)
  if [ "${LNBitsMigrate}" == "on" ]; then
    echo "# LNBitsMigrate=on --> Cleaning old lnbits_db & lnbits_user"
    sudo -u postgres psql -c "drop database lnbits_db;"
    sudo -u postgres psql -c "drop user lnbits_user;"
  fi
  # create database for new installations and keep old
  sudo -u postgres psql -c "create database lnbits_db;" 2>/dev/null
  sudo -u postgres psql -c "create user lnbits_user with encrypted password 'raspiblitz';" 2>/dev/null
  sudo -u postgres psql -c "grant all privileges on database lnbits_db to lnbits_user;" 2>/dev/null

  # check
  check=$(sudo -u postgres psql -c "SELECT datname FROM pg_database;" | grep lnbits_db)
  if [ "$check" = "" ]; then
    echo "# postgresConfig failed -> SELECT datname FROM pg_database;"
    exit 1
  else
    echo "# Setup PostgreSQL successful, new database found: $check"
  fi

  /home/admin/config.scripts/blitz.conf.sh set LNBitsDB "PostgreSQL"
}

function migrateMsg() {
  source <(/home/admin/_cache.sh get LNBitsDB)
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      echo "SUCCESS - A backup file was found. The migrate progress will revert automatically on failure."
      echo "For yet unknown reasons, this could be done manually with unpacking the SQLite backup file."
      echo
      echo "/home/admin/config.scripts/bonus.lnbits.sh migrate revert"
      echo
      echo "********************************************************"
      echo "*                                                      *"
      echo "* Revert: /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar *"
      echo "*                                                      *"
      echo "********************************************************"
      echo
    else
      echo "You dont have any migration backup files!"
    fi
  else
    echo "ABORT - Your LNBits is still running on old SQLite database."
    echo "Check for errors, '.dump' and fix your database manually and try again."
  fi
}

function revertMigration() {
  source <(/home/admin/_cache.sh get LNBitsMigrate)
  if [ "${LNBitsMigrate}" == "on" ]; then
    echo "# Revert migration, restore SQLite..."
    sudo systemctl stop lnbits

    # check current backup
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      echo "# Unpack Backup"
      cd /mnt/hdd/app-data/
      sudo rm -R /mnt/hdd/app-data/LNBits
      sudo tar -xf /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar
      sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits
    else
      echo "# No backup file found!"
    fi

    # update config
    echo "# Configure config .env"
    sudo sed -i "/^LNBITS_DATABASE_URL=/d" $lnbitsConfig

    # clean up
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"

    # start service
    echo "# Start LNBits"
    sudo systemctl start lnbits

    # set blitz config
    /home/admin/config.scripts/blitz.conf.sh set LNBitsMigrate "off"
    /home/admin/config.scripts/blitz.conf.sh set LNBitsDB "SQLite"

    echo "# OK revert migration done"
  else
    echo "# No migration started yet, nothing to do."
  fi
}

function readBackupBackend() {
  # Prefer the persisted backend to the cache. Check the active DSN without logging credentials.
  if [ -z "${LNBitsDB:-}" ]; then source <(/home/admin/_cache.sh get LNBitsDB); fi
  if sudo grep -Eq '^[[:space:]]*LNBITS_DATABASE_URL=.+[^[:space:]]' "$lnbitsConfig"; then
    if sudo grep -Eq "^LNBITS_DATABASE_URL=['\"]?postgres(ql)?://[^/@]*@localhost(:5432)?/lnbits_db['\"]?$" "$lnbitsConfig"; then
      LNBitsDB=PostgreSQL
    else
      echo "error='Unrecognized LNbits database URL; verify a backup before migrating'"
      return 1
    fi
  fi
  case "${LNBitsDB:-SQLite}" in PostgreSQL|SQLite) ;; *) echo "error='Unknown LNbits backup backend'"; return 1 ;; esac
}

# The caller keeps the service stopped throughout backup or restore.
function backupDatabase() {
  readBackupBackend || return 1
  echo "# Start Backup LNBits ${LNBitsDB} database"
  # older SQLite backups contain the LNbits config with the credentials of the funding source
  sudo chmod 600 /mnt/hdd/app-data/backup/lnbits_sqlite/*.tar /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar* 2>/dev/null
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    # postgresql backup
    sudo /home/admin/config.scripts/bonus.postgresql.sh backup lnbits_db || return 1
  else
    # sqlite backup
    backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
    backup_file="lnbits_sqlite_$(date +%d)-$(date +%m)-$(date +%Y)_$(date +%H)-$(date +%M)_fs.tar"
    if [ ! -d $backup_target ]; then
      sudo mkdir -p $backup_target 1>&2
    fi
    # Publish a complete private archive before rotating older copies.
    local tmp
    tmp=$(sudo mktemp "$backup_target/.lnbits.XXXXXXXX") || return 1
    if ! sudo tar -cf "$tmp" -C /mnt/hdd/app-data LNBits/ || ! sudo test -s "$tmp"; then
      sudo rm -f -- "$tmp"
      return 1
    fi
    backup_file="${backup_file%.tar}_${tmp##*.}.tar"
    sudo chown admin:admin "$tmp" && sudo mv -T "$tmp" "$backup_target/$backup_file" || { sudo rm -f -- "$tmp"; return 1; }
    ls -tp "$backup_target"/*.tar | tail -n +4 | tr '\n' '\0' | sudo xargs -0 -r rm --
    echo "OK - Backup finished, file saved as ${backup_target}/${backup_file}"
  fi
}

# show info menu
if [ "$1" = "menu" ]; then

  # get LNbits status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.lnbits.sh status)

  # display possible problems with IP2TOR setup
  if [ ${#ip2torWarn} -gt 0 ]; then
    whiptail --title " Warning " \
      --yes-button "Back" \
      --no-button "Continue Anyway" \
      --yesno "Your IP2TOR+LetsEncrypt may have problems:\n${ip2torWarn}\n\nCheck if locally responding: https://${localIP}:${httpsPort}\n\nCheck if service is reachable over Tor:\n${toraddress}" 14 72
    if [ "$?" != "1" ]; then
      exit 0
    fi
  fi

  # add info on funding source
  fundinginfo=""
  if [ "${LNBitsFunding}" == "lnd" ] || [ "${LNBitsFunding}" == "tlnd" ] || [ "${LNBitsFunding}" == "slnd" ]; then
    fundinginfo="on LND "
  elif [ "${LNBitsFunding}" == "cl" ] || [ "${LNBitsFunding}" == "tcl" ] || [ "${LNBitsFunding}" == "scl" ]; then
    fundinginfo="on CLN "
  fi

  text="https://${localIP}:${httpsPort}"

  if [ ${#publicDomain} -gt 0 ]; then
    text="${text}
Public Domain: https://${publicDomain}:${httpsPort}
port forwarding on router needs to be active & may change port"
  fi

  text="${text}\n
You need to accept self-signed HTTPS cert with SHA1 Fingerprint:
${sslFingerprintIP}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    text="${text}\n
TOR Browser Hidden Service address (QR see LCD):
${toraddress}"
  fi

  whiptail --title " LNbits ${fundinginfo}" --yes-button "OK" --no-button "OPTIONS" --yesno "${text}" 15 78
  result=$?
  sudo /home/admin/config.scripts/blitz.display.sh hide
  echo "option (${result}) - please wait ..."

  # exit when user presses OK to close menu
  if [ ${result} -eq 0 ]; then
    exit 0
  fi

  # LNbits OPTIONS menu
  OPTIONS=()

  # IP2TOR options
  if [ "${ip2torDomain}" != "" ]; then
    # IP2TOR+LetsEncrypt active - offer cancel
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  elif [ "${ip2torIP}" != "" ]; then
    # just IP2TOR active - offer cancel or Lets Encrypt
    OPTIONS+=(HTTPS-ON "Add free HTTPS-Certificate for LNbits")
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  fi

  # Change Funding Source options (only if available)
  if [ "${LNBitsFunding}" == "lnd" ] && [ "${cl}" == "on" ]; then
    OPTIONS+=(SWITCH-CL "Switch: Use CLN as funding source")
  elif [ "${LNBitsFunding}" == "cl" ] && [ "${lnd}" == "on" ]; then
    OPTIONS+=(SWITCH-LND "Switch: Use LND as funding source")
  fi

  # Backup database
  OPTIONS+=(BACKUP "Backup database")
  if [ -d /mnt/hdd/app-data/backup ]; then
    OPTIONS+=(RESTORE "Restore database")
  fi

  # Migrate SQLite to PostgreSQL
  if [ -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    OPTIONS+=(MIGRATE-DB "Migrate SQLite to PostgreSQL database")
  fi

  # Admin UI
  activatedAdminUI=$(sudo grep -c "LNBITS_ADMIN_UI=true" $lnbitsConfig)
  if [ ${activatedAdminUI} -eq 0 ]; then
    OPTIONS+=(ADMINUI "Activate 'Admin UI'")
  else
    OPTIONS+=(ADMINUI "Deactivate 'Admin UI'")
  fi

  # Allow New Accounts (only if AdminUI is OFF)
  # new accounts are off by default since LNbits v1.7.0
  allowNewAccounts=$(sudo grep -c "^LNBITS_ALLOW_NEW_ACCOUNTS=true" $lnbitsConfig)
  if [ ${activatedAdminUI} -eq 0 ]; then
    if [ ${allowNewAccounts} -eq 0 ]; then
      OPTIONS+=(NEWACCOUNTS "Enable New Accounts")
    else
      OPTIONS+=(NEWACCOUNTS "Disable New Accounts")
    fi
  fi

  WIDTH=66
  CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
  HEIGHT=$((CHOICE_HEIGHT + 7))
  CHOICE=$(dialog --clear \
    --title " LNbits - Options" \
    --ok-label "Select" \
    --cancel-label "Back" \
    --menu "Choose one of the following options:" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${OPTIONS[@]}" \
    2>&1 >/dev/tty)

  case $CHOICE in
  HTTPS-ON)
    python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py create-ssh-dialog
    exit 0
    ;;
  SWITCH-CL)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh switch cl
    echo "Restarting LNbits ..."
    sudo systemctl restart lnbits
    echo
    echo "OK new funding source for LNbits active."
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  SWITCH-LND)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh switch lnd
    echo "Restarting LNbits ..."
    sudo systemctl restart lnbits
    echo
    echo "OK new funding source for LNbits active."
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  BACKUP)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh backup
    backupResult=$?
    echo
    if [ "$backupResult" = 0 ]; then echo "Backup done"; else echo "LNbits backup failed"; fi
    echo "PRESS ENTER to continue"
    read key
    exit "$backupResult"
    ;;
  ADMINUI)
    clear
    echo
    if [ ${activatedAdminUI} -eq 0 ]; then
      echo "Activate Admin UI"
      sudo sed -i "/^LNBITS_ADMIN_UI=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ADMIN_UI=true' >> ${lnbitsConfig}"
    else
      echo "Deactivate Admin UI"
      sudo sed -i "/^LNBITS_ADMIN_UI=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ADMIN_UI=false' >> ${lnbitsConfig}"
    fi
    echo "Restarting LNbits to activate new setting ..."
    sudo systemctl restart lnbits
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  NEWACCOUNTS)
    clear
    echo
    if [ ${allowNewAccounts} -eq 0 ]; then
      echo "Enable New Accounts"
      sudo sed -i "/^LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo sed -i "/^# LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ALLOW_NEW_ACCOUNTS=true' >> ${lnbitsConfig}"
    else
      echo "Disable New Accounts"
      sudo sed -i "/^LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo sed -i "/^# LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ALLOW_NEW_ACCOUNTS=false' >> ${lnbitsConfig}"
    fi
    echo "Restarting LNbits to activate new setting ..."
    sudo systemctl restart lnbits
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  RESTORE)
    clear
    # check if backup exist
    readBackupBackend || exit 1
    if [ "${LNBitsDB}" == "PostgreSQL" ]; then
      backup_target="/mnt/hdd/app-data/backup/lnbits_db"
      backup_file=$(ls -t $backup_target/*.sql | head -n1)
    else
      backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
      backup_file=$(ls -t $backup_target/*.tar | head -n1)
    fi
    if [ "$backup_file" = "" ]; then
      echo "ABORT - No Backup found to restore from"
      exit 1
    else
      # build dialog to choose backup file from menu
      OPTIONS_RESTORE=()

      counter=0
      cd $backup_target
      for f in $(find *.* -maxdepth 1 -type f); do
        [[ -f "$f" ]] || continue
        counter=$(($counter + 1))
        OPTIONS_RESTORE+=($counter "$f")
      done

      WIDTH_RESTORE=66
      CHOICE_HEIGHT_RESTORE=$(("${#OPTIONS_RESTORE[@]}/2+1"))
      HEIGHT_RESTORE=$((CHOICE_HEIGHT_RESTORE + 7))
      CHOICE_RESTORE=$(dialog --clear \
        --title " LNbits - Backup restore" \
        --ok-label "Select" \
        --cancel-label "Back" \
        --menu "Choose one of the following backups:" \
        $HEIGHT_RESTORE $WIDTH_RESTORE $CHOICE_HEIGHT_RESTORE \
        "${OPTIONS_RESTORE[@]}" \
        2>&1 >/dev/tty)

      # start restore with selected backup
      clear
      if [ "$CHOICE_RESTORE" != "" ]; then
        backup_file=${backup_target}/${OPTIONS_RESTORE[$(($CHOICE_RESTORE * 2 - 1))]}
        /home/admin/config.scripts/bonus.lnbits.sh restore "${backup_file}"
        restoreResult=$?
        echo
        if [ "$restoreResult" = 0 ]; then echo "Restore done"; else echo "LNbits restore failed"; fi
        echo "PRESS ENTER to continue"
        read key
        exit "$restoreResult"
      fi
      exit 0
    fi
    ;;
  MIGRATE-DB)
    clear
    dialog --title "MIGRATE LNBITS" --yesno "
Do you want to proceed the migration?

Try to migrate your LNBits SQLite database to PostgreSQL.

This can fail for unknown circumstances. Revert of this process is possible afterwards, a backup will be saved.
            " 12 65
    if [ $? -eq 0 ]; then
      clear
      /home/admin/config.scripts/bonus.lnbits.sh migrate
      echo
      migrateMsg
      echo
      echo "OK please test your LNBits installation."
      echo "PRESS ENTER to continue"
      read key
    fi
    exit 0
    ;;
  *)
    clear
    exit 0
    ;;
  esac

  exit 0
fi

# status
if [ "$1" = "status" ]; then

  echo "version='${VERSION}'"

    fatpack=$(compgen -u | grep -c lnbits)
    echo "fatpack=${fatpack}"

  if [ "${LNBits}" = "on" ]; then
    echo "installed=1"

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='5000'"
    echo "httpsPort='5001'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'" # TODO: change later if IP2Tor+LetsEncrypt is active
    echo "publicIP='${publicIP}'"

    # auth method is web login
    echo "authMethod='userdefined'"

    # check funding source
    if [ "${LNBitsFunding}" == "" ]; then
      LNBitsFunding="lnd"
    fi
    echo "LNBitsFunding='${LNBitsFunding}'"

    sslFingerprintIP=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintIP='${sslFingerprintIP}'"

    toraddress=$(sudo cat /mnt/hdd/app-data/tor/lnbits/hostname 2>/dev/null)
    echo "toraddress='${toraddress}'"

    sslFingerprintTOR=$(openssl x509 -in /mnt/hdd/app-data/nginx/tor_tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintTOR='${sslFingerprintTOR}'"

    # check for error
    isDead=$(sudo systemctl status lnbits | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 0
    fi

  else
    echo "installed=0"
  fi
  exit 0
fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user lnbits)
#########################

if [ "$1" = "prestart" ]; then

  # users need to be `lnbits` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "lnbits" ]; then
    echo "# FAIL: run as user lnbits"
    exit 1
  fi

  # get if its for lnd or cl service
  echo "## lnbits.service PRESTART CONFIG"
  echo "# --> ${lnbitsConfig}"

  # set values based in funding source in raspiblitz config
  # portprefix is "" |  1 | 3
  LNBitsNetwork="bitcoin"
  LNBitsChain=""
  LNBitsLightning=""
  if [ "${LNBitsFunding}" == "" ] || [ "${LNBitsFunding}" == "lnd" ]; then
    LNBitsFunding="lnd"
    LNBitsLightning="lnd"
    LNBitsChain="main"
    portprefix=""
  elif [ "${LNBitsFunding}" == "tlnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="test"
    portprefix="1"
  elif [ "${LNBitsFunding}" == "slnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="sig"
    portprefix="3"
  elif [ "${LNBitsFunding}" == "cl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="main"
  elif [ "${LNBitsFunding}" == "tcl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="test"
  elif [ "${LNBitsFunding}" == "scl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="sig"
  else
    echo "# FAIL: Unknown LNBitsFunding=${LNBitsFunding}"
    exit 1
  fi

  echo "# LNBitsFunding(${LNBitsFunding}) --> network(${LNBitsNetwork}) chain(${LNBitsChain}) lightning(${LNBitsLightning})"

  # set lnd config
  if [ "${LNBitsLightning}" == "lnd" ]; then

    echo "# setting lnd config fresh ..."

    # check if lnbits user has read access on lnd data files
    checkReadAccess=$(cat /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon | grep -c "lnd")
    if [ "${checkReadAccess}" != "1" ]; then
      echo "# FAIL: missing lnd data in '/mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon' or missing access rights for lnbits user"
      exit 1
    fi

    echo "# Updating LND TLS & macaroon data fresh for LNbits config ..."

    # set tls.cert path (use | as separator to avoid escaping file path slashes)
    sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=/mnt/hdd/app-data/lnd/tls.cert|g" $lnbitsConfig
    # set macaroon  path info in .env - USING HEX IMPORT
    chmod 600 $lnbitsConfig
    macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon)
    macaroonInvoiceHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/invoice.macaroon)
    macaroonReadHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/readonly.macaroon)
    sed -i "s/^LND_REST_ADMIN_MACAROON=.*/LND_REST_ADMIN_MACAROON=${macaroonAdminHex}/g" $lnbitsConfig
    sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" $lnbitsConfig
    sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" $lnbitsConfig
    # set the REST endpoint (use | as separator to avoid escaping slashes)
    sed -i "s|^LND_REST_ENDPOINT=.*|LND_REST_ENDPOINT=https://127.0.0.1:${portprefix}8080|g" $lnbitsConfig

    echo "# Checking if LND REST API is responding ..."
    count=0
    while ! curl -s -k --head --request GET "https://127.0.0.1:${portprefix}8080/v1/getinfo" > /dev/null; do
      count=$((count + 1))
      if [ $count -gt 600 ]; then
        echo "# FAIL: LND REST API did not respond after 10 minutes."
        exit 1
      fi
      echo "# Waiting for LND REST API... (${count}s/600s)"
      sleep 1
    done
    echo "# OK: LND REST API is responding."

  elif [ "${LNBitsLightning}" == "cl" ]; then

    isUsingCL=$(cat $lnbitsConfig | grep -c "LNBITS_BACKEND_WALLET_CLASS=CLightningWallet")
    if [ "${isUsingCL}" != "1" ]; then
      echo "# FAIL: ${lnbitsConfig} not set to CLN"
      exit 1
    fi

    CLIGHTNING_RPC=$(grep '^CLIGHTNING_RPC=' ${lnbitsConfig} | cut -d'=' -f2-)
    while ! lightning-cli --rpc-file=${CLIGHTNING_RPC} getinfo &> /dev/null; do
      echo "Waiting for CLN RPC socket to become available..."
      sleep 1
    done

    echo "# everything looks OK for lnbits config on CLN on ${LNBitsChain}net"

  else
    echo "# FAIL: missing or not supported LNBitsLightning=${LNBitsLightning}"
    exit 1
  fi

  # protect the admin user id if exists
  chmod 640 /mnt/hdd/app-data/LNBits/data/.super_user 2>/dev/null

  echo "# OK: prestart finished"
  exit 0 # exit with clean code
fi

if [ "$1" = "repo" ]; then

  # get github parameters
  githubUser="$2"
  if [ ${#githubUser} -eq 0 ]; then
    echo "echo='missing parameter'"
    exit 1
  fi
  githubBranch="$3"
  if [ ${#githubBranch} -eq 0 ]; then
    githubBranch="main"
  fi

  # check if repo exists
  githubRepo="https://github.com/${githubUser}/lnbits"

  httpcode=$(curl -s -o /dev/null -w "%{http_code}" ${githubRepo})
  if [ "${httpcode}" != "200" ]; then
    echo "# tested github repo: ${githubRepo}"
    echo "error='repo for user does not exist'"
    exit 1
  fi

  # fix permissions
  sudo chown -R lnbits:lnbits /home/lnbits/lnbits
  # change origin repo of lnbits code
  echo "# changing LNbits github repo(${githubUser}) branch(${githubBranch})"
  cd /home/lnbits/lnbits || exit 1
  sudo -u lnbits git remote remove origin
  sudo -u lnbits git remote add origin ${githubRepo}
  sudo -u lnbits git fetch
  sudo -u lnbits git checkout ${githubBranch}
  sudo -u lnbits git branch --set-upstream-to=origin/${githubBranch} ${githubBranch}

fi

if [ "$1" = "sync" ] || [ "$1" = "repo" ]; then
  echo "# pull all changes from github repo"
  # fix permissions
  sudo chown -R lnbits:lnbits /home/lnbits/lnbits
  # output basic info
  cd /home/lnbits/lnbits || exit 1
  sudo -u lnbits git remote -v
  sudo -u lnbits git branch -v
  # pull latest code
  sudo -u lnbits git pull

  echo "# install"
  installDependencies || exit 1
  setServiceExecStart

  echo "# restart lnbits service"
  sudo systemctl restart lnbits
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# Update records the previous state before stopping. An already configured
# service also remains running when 'on' reports that it is already active.
case "$1" in
  update|on|1) ;;
  backup|restore)
    backupWasActive=0
    restoreHeld=0
    if sudo test -f /etc/systemd/system/lnbits.service; then
      if systemctl is-active --quiet lnbits; then backupWasActive=1; fi
      if [ "$1" = restore ] && { ! sudo test -f "$updateDropIn" || sudo grep -qx '# operation=restore' "$updateDropIn"; }; then
        holdOperation=restore
        resumeService=$backupWasActive
        if sudo grep -qsx '# resume=1' "$updateDropIn"; then resumeService=1; fi
        holdLnbitsService || exit 1
        restoreHeld=1
      else
        sudo systemctl stop lnbits || exit 1
      fi
    fi ;;
  *) sudo systemctl stop lnbits 2>/dev/null ;;
esac

# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed (user exists and the dependencies are in place)
  if compgen -u | grep -w lnbits && sudo -u lnbits test -x ${lnbitsBin}; then
    echo "result='already installed'"
    exit 0
  fi

  # get optional github parameter
  githubUser="lnbits"
  if [ "$2" != "" ]; then
    githubUser="$2"
  fi
  if [ "$3" != "" ]; then
    tag="$3"
  fi

  echo "# *** INSTALL LNBITS ***"
  echo "# githubUser=$githubUser tag=$tag"

  # make sure dependencies are installed
  sudo apt-get install -y pkg-config build-essential python3-dev libsecp256k1-dev libffi-dev libgmp-dev

  # add lnbits user
  echo "*** Add the 'lnbits' user ***"
  sudo adduser --system --group --home /home/lnbits lnbits
  # add user to group bitcoin
  sudo usermod -a -G bitcoin lnbits

  # install from GitHub
  echo "# get the github code user(${githubUser}) branch(${tag})"
  sudo rm -r /home/lnbits/lnbits 2>/dev/null
  sudo -u lnbits git -C /home/lnbits clone -- "https://github.com/${githubUser}/lnbits" lnbits || exit 1
  sudo -u lnbits git -C "$lnbitsCodeDir" checkout "$tag" || exit 1
  # the default version has to be the pinned commit (not checked for an own repo, branch or tag)
  if [ "${githubUser}" = "lnbits" ] && [ "${tag}" = "${VERSION}" ]; then
    verifyCommit HEAD || exit 1
  fi

  # do the install
  exitCode=0
  if installDependencies; then
    echo "# Install of the dependencies completed successfully."
  else
    echo "Error: Install of the dependencies failed (see above).. waiting 10 seconds"
    exitCode=1
    sleep 10
  fi

  exit $exitCode
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL LNBITS ***"

  if sudo test -f "$updateDropIn"; then releaseLnbitsService || exit 1; fi
  # always delete user and home directory
  sudo userdel -rf lnbits

  exit 0
fi

# update an existing install to the LNbits version of this script
if [ "$1" = update ]; then
  updateMenu=0
  if [ "${2:-}" = --menu ]; then updateMenu=1; fi
  beforeCheckout=0
  previousActive=0
  resumeService=0
  previousCommit=""
  echo "# *** UPDATE LNBITS to $tag ***"

  sudo -u lnbits test -d "$lnbitsCodeDir/.git" || failLnbitsUpdate "LNbits is not installed"
  previousCommit=$(sudo -u lnbits git -C "$lnbitsCodeDir" rev-parse --verify HEAD) || failLnbitsUpdate "Cannot read the installed revision"
  installedVersion=$(sudo -u lnbits git -C "$lnbitsCodeDir" describe --tags --always)
  echo "# Installed version: $installedVersion"
  # Keep customised installs intact and refuse a downgrade after a newer migration.
  if [[ "$installedVersion" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
    installedNumber=${BASH_REMATCH[1]}
    if dpkg --compare-versions "${installedNumber/-rc/~rc}" gt "${tag#v}"; then
      failLnbitsUpdate "Installed release is newer than the update target"
    fi
  fi
  changes=$(sudo -u lnbits git -C "$lnbitsCodeDir" status --porcelain --untracked-files=no) || failLnbitsUpdate "Cannot check the working tree"
  [ -z "$changes" ] || failLnbitsUpdate "Installed LNbits has local changes"
  serviceInstalled=0
  if sudo test -f /etc/systemd/system/lnbits.service; then
    serviceInstalled=1
    supportedLnbitsUnit || failLnbitsUpdate "Custom LNbits service command needs a manual update"
    if sudo test -f "$updateDropIn"; then
      if sudo grep -qx '# operation=restore' "$updateDropIn"; then
        failLnbitsUpdate "Finish the pending database restore before updating"
      fi
      if sudo grep -qx '# resume=1' "$updateDropIn"; then resumeService=1; fi
      if sudo grep -qx "# restartable=$tagCommit" "$updateDropIn"; then previousActive=1; fi
    else
      state=$(systemctl show lnbits --property=ActiveState --value) || failLnbitsUpdate "Cannot read the service state"
      case "$state" in
        active) resumeService=1; if lnbitsHealthy; then previousActive=1; fi ;;
        inactive|failed) ;;
        *) failLnbitsUpdate "The service is changing state. Retry when it has settled" ;;
      esac
    fi
    holdLnbitsService || failLnbitsUpdate "Could not stop LNbits safely"
  fi

  beforeCheckout=1
  legacy=0
  if sudo -u lnbits test -d /home/lnbits/.cache/pypoetry; then legacy=1; fi

  # Keep the pre-upgrade backup on retries, including after a partial migration.
  if [ "$previousCommit" != "$tagCommit" ] || [ "$legacy" = 1 ]; then
    if sudo test -f "$lnbitsConfig"; then
      backupDatabase || failLnbitsUpdate "Database backup failed"
    elif [ "$serviceInstalled" = 1 ]; then
      failLnbitsUpdate "The configured service has no readable LNbits configuration"
    fi
  fi
  sudo -u lnbits git -C "$lnbitsCodeDir" fetch https://github.com/lnbits/lnbits "+refs/tags/${tag}:refs/tags/${tag}" ||
    failLnbitsUpdate "Download of the LNbits release failed"
  verifyCommit "refs/tags/$tag" || failLnbitsUpdate "Release verification failed"
  # A failed checkout may itself have changed files.
  beforeCheckout=0
  if [ "$serviceInstalled" = 1 ]; then
    sudo sed -i '/^# restartable=/d' "$updateDropIn" || failLnbitsUpdate "Cannot record the release change"
  fi
  sudo -u lnbits git -C "$lnbitsCodeDir" checkout "$tagCommit" || failLnbitsUpdate "Cannot check out the verified release"
  setServiceExecStart || failLnbitsUpdate "Cannot configure the updated service"
  installDependencies || failLnbitsUpdate "Installation of the release dependencies failed"

  if [ "$serviceInstalled" = 1 ]; then
    if [ "$resumeService" = 1 ]; then
      if ! startCheckedLnbits; then
        holdLnbitsService || failLnbitsUpdate "Health check failed and the service could not be stopped"
        failLnbitsUpdate "The updated LNbits did not pass its health check"
      fi
      echo "# LNbits $tag is running and healthy."
    else
      releaseLnbitsService || failLnbitsUpdate "Cannot release the service after installation"
      echo "# LNbits $tag is installed. The previously stopped service remains stopped."
    fi
  fi
  # A retry may already be at the target revision when first reaching success.
  securityNotice
  echo "result='OK'"
  exit 0
fi

# on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # A fresh system can have a funded data disk but no service or lnbits user.
  # Secure the persisted backend before installation can migrate it.
  if sudo test -f "$lnbitsConfig" && ! sudo test -f /etc/systemd/system/lnbits.service; then
    readBackupBackend || exit 1
    if [ "$LNBitsDB" = PostgreSQL ] && ! sudo -u postgres pg_isready -q &&
       sudo test -d /mnt/hdd/app-data/postgresql; then
      sudo /home/admin/config.scripts/bonus.postgresql.sh on || exit 1
    fi
    backupDatabase || { echo "error='Database backup failed; setup cancelled before reinstall'"; exit 1; }
  fi

  # check if already installed
  if compgen -u | grep -w lnbits; then
    # check the dependencies if the user exists (also replaces an old poetry based install)
    if ! sudo -u lnbits test -x ${lnbitsBin}; then
      echo "# Fix faulty installation"
      # replacing an old poetry based install (LNbits up to v1.2.1) is an update
      # (only if LNbits was in use: a fatpack image has the code but no config)
      if sudo test -f "$lnbitsConfig"; then
        showSecurityNotice=1
        # the database migrations of the new version cannot be reverted
        if sudo test -f /etc/systemd/system/lnbits.service; then
          # A configured legacy installation uses the same guarded update path.
          exec /home/admin/config.scripts/bonus.lnbits.sh update
        fi
      fi
      /home/admin/config.scripts/bonus.lnbits.sh off --keep-data || exit 1
      /home/admin/config.scripts/bonus.lnbits.sh install || exit 1
    fi
  else
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.lnbits.sh install || exit 1
  fi

  # check if already active
  isActive=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ "${isActive}" == "1" ]; then
    echo "# FAIL: already installed"
    exit 1
  fi

  # get funding source and check that its available
  fundingsource="$2"

  # run with default funding source if not given as parameter
  if [ "${fundingsource}" == "" ]; then
    echo "# running with default lightning as funing source: ${lightning}"
    fundingsource="${lightning}"
  fi

  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "# FAIL: lnd mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: CLN mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: CLN testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: CLN signet needs to be activated"
      exit 1
    fi

  else
    echo "# FAIL: invalid funding source parameter"
    exit 1
  fi

 # prepare data dir file
  sudo mkdir -p $lnbitsDataDir
  sudo chown lnbits:lnbits -R $lnbitsDataDir

  echo "# preparing env file"
  # delete old .env file or old symbolic link
  sudo rm /home/lnbits/lnbits/.env 2>/dev/null
    
  # make sure .env file exists at data drive
  if [ ! -f $lnbitsConfig ]; then
    sudo -u lnbits touch $lnbitsConfig
    sudo bash -c "echo 'LNBITS_ADMIN_UI=true' >> ${lnbitsConfig}"
  fi
  sudo chown lnbits:lnbits $lnbitsConfig

  # crete symbolic link
  sudo -u lnbits ln -s $lnbitsConfig /home/lnbits/lnbits/.env

  if [ ! -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    echo "# install database: PostgreSQL"

    # POSTGRES
    postgresConfig

    # config update
    # example: postgres://<user>:<password>@<host>/<database>
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    if ! sudo grep -q '^LNBITS_DATABASE_URL=.' "$lnbitsConfig"; then
      sudo sed -i '/^LNBITS_DATABASE_URL=/d' "$lnbitsConfig"
      sudo bash -c "echo 'LNBITS_DATABASE_URL=postgres://postgres:postgres@localhost:5432/lnbits_db' >> ${lnbitsConfig}"
    fi
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits/data' >> ${lnbitsConfig}"

  else

    echo "# install database: SQLite"
    /home/admin/config.scripts/blitz.conf.sh set LNBitsDB "SQLite"

    # new data directory
    sudo mkdir -p /mnt/hdd/app-data/LNBits

    # config update
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"
  fi
  sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits

  # open firewall
  echo
  echo "*** Updating Firewall ***"
  sudo ufw allow 5000 comment 'lnbits HTTP'
  sudo ufw allow 5001 comment 'lnbits HTTPS'
  echo

  # make sure that systemd starts funding source first
  systemdDependency="bitcoind.service"
  if [ "${fundingsource}" == "lnd" ]; then
    systemdDependency="lnd.service"
  elif [ "${fundingsource}" == "cl" ]; then
    systemdDependency="lightningd.service"
  fi

  # install service
  echo "*** Install systemd ***"
  cat <<EOF | sudo tee /etc/systemd/system/lnbits.service >/dev/null
# systemd unit for lnbits

[Unit]
Description=lnbits
Wants=${systemdDependency}
After=${systemdDependency}
PartOf=${systemdDependency}

[Service]
WorkingDirectory=/home/lnbits/lnbits
ExecStartPre=/home/admin/config.scripts/bonus.lnbits.sh prestart
ExecStart=${lnbitsExecStart}
User=lnbits
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

  # let switch command part do the detail config
  /home/admin/config.scripts/bonus.lnbits.sh switch ${fundingsource}
  cd /home/lnbits/lnbits || exit 1

  sudo systemctl enable lnbits

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - lnbits service is enabled, system is on ready so starting lnbits service"
    sudo systemctl start lnbits
  else
    echo "# OK - lnbits service is enabled, but needs reboot or manual starting: sudo systemctl start lnbits"
  fi

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/lnbits_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-available/lnbits_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-available/lnbits_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-available/lnbits_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set LNBits "on"

  # Hidden Service if Tor is active
  source /mnt/hdd/app-data/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
  fi

  echo "# OK install done ... might need to restart or call: sudo systemctl start lnbits"

  if [ "${showSecurityNotice}" = "1" ]; then
    securityNotice
  fi

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# config for a special funding source (e.g lnd or CLN as backend)
if [ "$1" = "switch" ]; then

  echo "## bonus.lnbits.sh switch $2"

  # get funding source and check that its available
  fundingsource="$2"
  clrpcsubdir=""
  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "#FAIL: lnd mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: CLN mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    clrpcsubdir="/testnet"
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: CLN testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    clrpcsubdir="/signet"
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: CLN signet not installed or running"
      exit 1
    fi

  else
    echo "# FAIL: unvalid fundig source parameter"
    exit 1
  fi

  # make lnd.service fallback
  sudo sed -i 's/Wants=lnd.service/Wants=bitcoind.service/' /etc/systemd/system/lnbits.service
  sudo sed -i 's/After=lnd.service/After=bitcoind.service/' /etc/systemd/system/lnbits.service

  echo "##############"
  echo "# NOTE: If you switch the funding source of a running LNbits instance all sub account will keep balance."
  echo "# Make sure that the new funding source has enough sats to cover the LNbits bookeeping of sub accounts."
  echo "##############"

  # remove all old possible settings for former funding source (clean state)
  sudo sed -i "/^LNBITS_BACKEND_WALLET_CLASS=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_ENDPOINT=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_CERT=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_ADMIN_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_INVOICE_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_READ_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo /usr/sbin/usermod -G lnbits lnbits
  sudo sed -i "/^CLIGHTNING_RPC=/d" $lnbitsConfig 2>/dev/null

  # LND CONFIG
  if [ "${fundingsource}" == "lnd" ] || [ "${fundingsource}" == "tlnd" ] || [ "${fundingsource}" == "slnd" ]; then

    # make sure lnbits user can access LND credentials
    echo "# adding lnbits user is member of lndreadonly, lndinvoice, lndadmin"
    sudo /usr/sbin/usermod --append --groups lndinvoice lnbits
    sudo /usr/sbin/usermod --append --groups lndreadonly lnbits
    sudo /usr/sbin/usermod --append --groups lndadmin lnbits

    # prepare config entries in lnbits config for lnd
    echo "# preparing lnbits config for lnd"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=LndRestWallet' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_ENDPOINT=https://127.0.0.1:8080' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_CERT=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_ADMIN_MACAROON=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_INVOICE_MACAROON=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_READ_MACAROON=' >> ${lnbitsConfig}"

  fi

  if [ "${fundingsource}" == "cl" ] || [ "${fundingsource}" == "tcl" ] || [ "${fundingsource}" == "scl" ]; then

    echo "# add the 'lnbits' user to the 'bitcoin' group"
    sudo /usr/sbin/usermod --append --groups bitcoin lnbits
    echo "# check user"
    id lnbits

    echo "# allowing lnbits user as part of the bitcoin group to RW RPC hook"
    sudo chmod 770 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}
    sudo chmod 660 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}/lightning-rpc
    if [ "${fundingsource}" == "cl" ]; then
      CLCONF="/home/bitcoin/.lightning/config"
    else
      CLCONF="/home/bitcoin/.lightning${clrpcsubdir}/config"
    fi
    # https://github.com/rootzoll/raspiblitz/issues/3007
    if [ "$(sudo cat ${CLCONF} | grep -c "^rpc-file-mode=0660")" -eq 0 ]; then
      echo "rpc-file-mode=0660" | sudo tee -a ${CLCONF}
    fi

    echo "# preparing lnbits config for CLN"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=CLightningWallet' >> ${lnbitsConfig}"
    sudo bash -c "echo 'CLIGHTNING_RPC=/home/bitcoin/.lightning/bitcoin${clrpcsubdir}/lightning-rpc' >> ${lnbitsConfig}"
  fi

  # set raspiblitz config value for funding
  /home/admin/config.scripts/blitz.conf.sh set LNBitsFunding "${fundingsource}"

  echo "##############"
  echo "# OK new funding source set - does need restart or call: sudo systemctl restart lnbits"
  echo "##############"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe LNbits Server Data?" 8 30); then
      deleteData=1
    else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"
  echo "*** REMOVING LNbits ***"

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 1 ]; then
    sudo systemctl stop lnbits && sudo systemctl disable lnbits &&
      sudo rm /etc/systemd/system/lnbits.service || exit 1
    echo "# OK lnbits.service removed."
  else
    echo "# lnbits.service is not installed."
  fi
  if sudo test -f "$updateDropIn"; then releaseLnbitsService || exit 1; fi

  echo "# Cleaning up LNbits install ..."
  sudo ufw delete allow 5000
  sudo ufw delete allow 5001

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off lnbits
  fi

  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting data"
    sudo -u postgres psql -c "drop database lnbits_db;"
    sudo -u postgres psql -c "drop user lnbits_user;"
    sudo rm /home/lnbits/lnbits/.env
    sudo rm -R /mnt/hdd/app-data/LNBits
  else
    echo "# keeping data"
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set LNBits "off"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# backup
if [ "$1" = "backup" ]; then
  backupDatabase
  backupResult=$?
  if [ "$backupWasActive" = 1 ]; then sudo systemctl start lnbits || exit 1; fi
  exit "$backupResult"
fi

# restore
if [ "$1" = "restore" ]; then
  readBackupBackend || exit 1
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    echo "# Restore PostgreSQL database"
    if [ "$2" != "" ]; then
      backup_file=$2
      sudo /home/admin/config.scripts/bonus.postgresql.sh restore lnbits_db lnbits_user raspiblitz "${backup_file}" || exit 1
    else
      sudo /home/admin/config.scripts/bonus.postgresql.sh restore lnbits_db lnbits_user raspiblitz || exit 1
    fi
  else
    backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
    if [ ! -d $backup_target ]; then
      echo "# ABORT - No backups found"
      exit 1
    else
      echo "# Restore SQLite database"
      cd "$backup_target" || exit 1

      if [ "$2" != "" ]; then
        if [ -f "$2" ]; then
          backup_file=$2
        else
          echo "ABORT - File not found (${2})"
          exit 1
        fi
      else
        # find recent backup
        backup_file=$(ls -t $backup_target/*.tar | head -n1)
      fi

      echo "Start restore from backup ${backup_file}"

      staging=$(sudo mktemp -d /mnt/hdd/app-data/.lnbits-restore.XXXXXXXX) || exit 1
      if ! sudo python3 - "$backup_file" "$staging" <<'PY'
from pathlib import Path, PurePosixPath
import sqlite3, sys, tarfile

root = Path(sys.argv[2])
with tarfile.open(sys.argv[1]) as archive:
    for member in archive:
        parts = PurePosixPath(member.name).parts
        if not parts or parts[0] != "LNBits" or ".." in parts or not (member.isfile() or member.isdir()):
            raise SystemExit("Unsupported member in LNbits backup")
        archive.extract(member, root, filter="data")
app = root / "LNBits"
if not (app / "data" / ".env").is_file():
    raise SystemExit("Missing LNbits configuration in backup")
db = next((p for p in (app / "database.sqlite3", app / "data" / "database.sqlite3") if p.is_file()), None)
if db is None:
    raise SystemExit("Missing LNbits database in backup")
with sqlite3.connect(db.as_uri() + "?mode=ro", uri=True) as conn:
    conn.execute("SELECT id, name FROM wallets LIMIT 0")
    if conn.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
        raise SystemExit("SQLite integrity check failed")
PY
      then
        sudo rm -rf -- "$staging"
        exit 1
      fi
      if ! sudo chown -R lnbits:lnbits "$staging/LNBits" || ! backupDatabase; then
        sudo rm -rf -- "$staging"
        exit 1
      fi
      # Publish and preserve the old directory in one Linux filesystem operation.
      # Both an interruption and an unsupported filesystem leave a live directory.
      sudo mv -T "$staging/LNBits" "$staging/previous" || exit 1
      sudo python3 - /mnt/hdd/app-data/LNBits "$staging/previous" <<'PY' || exit 1
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
at_fdcwd, rename_exchange = -100, 2
if libc.renameat2(at_fdcwd, os.fsencode(sys.argv[1]), at_fdcwd, os.fsencode(sys.argv[2]), rename_exchange):
    err = ctypes.get_errno()
    raise OSError(err, os.strerror(err))
PY
      echo "# Previous data retained in $staging/previous until you verify the restored wallet"

      echo "OK - Apply backup data successful"
    fi
  fi

  if [ "$restoreHeld" = 1 ]; then
    if [ "$resumeService" = 0 ]; then
      releaseLnbitsService || exit 1
    elif ! startCheckedLnbits; then
      holdLnbitsService || { echo "# Failed to stop LNbits after restore"; exit 1; }
      echo "# Restored application failed its health check. LNbits has been stopped."
      exit 1
    fi
  elif sudo test -f "$updateDropIn"; then
    echo "# Wallet data restored. LNbits remains stopped; retry the pending update in the Update menu."
  fi
  exit 0
fi

# revert migrate to postgresql
if [ "$1" = "migrate" ] && [ "$2" = "revert" ]; then
  /home/admin/config.scripts/blitz.conf.sh set LNBitsMigrate "on"
  revertMigration
  exit 0
fi

# migrate
if [ "$1" = "migrate" ]; then

  if [ -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    echo "# Backup SQLite database"
    # backup current database, but dont overwrite last backup
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old ]; then
        echo "# Remove old backup file"
        sudo rm -f /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old
      fi
      # keep the last backup as old backup
      sudo mv /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old
      sudo chmod 600 /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old
    fi
    # create new backup (contains the LNbits config with the credentials of the funding source)
    sudo touch /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar
    sudo chmod 600 /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar
    sudo tar -cf /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar -C /mnt/hdd/app-data LNBits/

    # restore sqlite database config
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"

    # stop after sync was done
    sudo systemctl stop lnbits

    /home/admin/config.scripts/blitz.conf.sh set LNBitsMigrate "on"

    # POSTGRES
    postgresConfig

    # example: postgres://<user>:<password>@<host>/<database>
    # add new postgres config
    sudo sed -i "/^LNBITS_DATABASE_URL=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATABASE_URL=postgres://lnbits_user:raspiblitz@localhost:5432/lnbits_db' >> ${lnbitsConfig}"

    # clean start on new postgres db prior migration
    echo "# LNBits first start with clean PostgreSQL"
    sudo systemctl start lnbits

    # execStartPre is not enough, wait for lnbits is finally running
    count=0
    count_max=30
    while ! nc -zv 127.0.0.1 5000 2>/dev/null; do
      count=$(expr $count + 1)
      echo "wait for LNBIts to start (${count}s/${count_max}s)"
      sleep 1
      if [ $count = $count_max ]; then
        sudo systemctl status lnbits
        echo "# FAIL - LNBits service was not able to start"
        revertMigration
        exit 1
      fi
    done
    # wait a sec for "âœ” All migrations done." (TODO make it pretty)
    sleep 5
    echo "# LNBits service looks good"
    sudo systemctl stop lnbits

    echo "# Start convert old SQLite to new PostgreSQL"
    # known issue (as before): the conversion cannot run (psycopg2 is not installed, wrong
    # working directory) and the cleanup below also deletes the LNbits config in the data
    # directory. Dont make the conversion work before that cleanup is reworked.
    if ! sudo -u lnbits ${lnbitsCodeDir}/.venv/bin/python tools/conv.py; then
      echo "FAIL - Convert failed, revert migration process"
      revertMigration
      exit 1
    else
      echo "# OK - Convert successful"
    fi

    # cleanup old sqlite data directory
    echo "# Cleanup old data directory"
    sudo rm -R /mnt/hdd/app-data/LNBits/
    # new data directory
    sudo mkdir -p /mnt/hdd/app-data/LNBits/data
    sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits/

    echo "# Configure .env"
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits/data' >> ${lnbitsConfig}"

    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set LNBitsMigrate "off"

    echo "# OK - migration done"
  else
    echo "# ABORT - No SQLite data found to migrate from"
  fi

  sudo systemctl start lnbits
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
