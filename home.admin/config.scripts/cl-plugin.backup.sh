#!/bin/bash

function help() {
  echo
  echo "Install the backup plugin for Core Lightning"
  echo "Replicates the lightningd.sqlite3 database on the SDcard"
  echo
  echo "Usage:"
  echo "cl-plugin.backup.sh [on|off] [testnet|mainnet|signet]"
  echo "cl-plugin.backup.sh [restore] [testnet|mainnet|signet] [force]"
  echo "cl-plugin.backup.sh [backup-compact] [testnet|mainnet|signet]"
  echo
  echo "https://github.com/lightningd/plugins/tree/master/backup"
  echo
  exit 1
}

# https://github.com/lightningd/plugins/commits/master/backup
pinnedVersion="b63622d66ea8cfaa1e99fde1626ae86815ad1be8"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  help
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

plugin="backup"
plugindir="/home/bitcoin/cl-plugins-available/plugins"
dbPath="/home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3"
backupPath="/home/bitcoin/${netprefix}lightningd.sqlite3.backup"

function read_db_size() {
  local dbBytes
  if [ "$1" = on ] && sudo test -x "${dbPath%/*}" &&
    sudo test ! -e "${dbPath}" && sudo test ! -L "${dbPath}"; then
    # backup-cli also supports initialization before the first database exists.
    dbKiB=0
  else
    if ! sudo test -f "${dbPath}"; then
      echo "Cannot read CLN database size at ${dbPath}." >&2
      return 1
    fi
    dbBytes=$(sudo stat -Lc %s -- "${dbPath}") || return 1
    dbKiB=$(( (dbBytes + 1023) / 1024 ))
  fi
}

function check_backup_space() {
  local destination="$1" copies="$2" availableKiB minimumKiB message
  availableKiB=$(LC_ALL=C sudo df -Pk -- "${destination}" | awk 'NR==2 {print $4}')
  if ! [[ "${availableKiB}" =~ ^[0-9]+$ ]]; then
    echo "Cannot determine available CLN backup space on ${destination}." >&2
    return 1
  fi
  minimumKiB=$(( dbKiB * copies + 200 * 1024 ))
  if (( availableKiB < minimumKiB )); then
    message="Low CLN backup space on ${destination}: ${availableKiB} KiB available, need at least ${minimumKiB} KiB. Free space while preserving the recovery backup."
    echo "${message}" >&2
    logger -t raspiblitz-cl-backup -- "${message}"
    return 1
  fi
}

function install() {
  if [ ! -f "${plugindir}/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi
  cd ${plugindir} || exit 1
  sudo -u bitcoin git pull
  sudo -u bitcoin git reset --hard ${pinnedVersion} || exit 1

  if [ $($lightningcli_alias plugin list 2>/dev/null | grep -c "/${plugin}") -eq 0 ]; then
    echo "# Checking dependencies"
    # uv should be installed from main CLN install
    if ! command -v uv &>/dev/null; then
      echo "# Installing uv for backup plugin"
      curl -LsSf https://astral.sh/uv/install.sh | sudo UV_INSTALL_DIR=/usr/local/bin sh
      export PATH="/usr/local/bin:$PATH"
    fi
    
    cd ${plugindir}/backup/ || exit 1
    sudo -u bitcoin uv sync --all-extras

    sudo chmod +x ${plugindir}/${plugin}/${plugin}.py

    # symlink to the default plugin dir
    if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/backup.py ]; then
      sudo ln -s ${plugindir}/backup/backup.py \
        /home/bitcoin/${netprefix}cl-plugins-enabled/
    fi
  else
    echo "# The ${plugin} plugin is already loaded"
  fi

  # make sure the default virtualenv is used
  sudo apt-get remove -y python3-virtualenv 2>/dev/null
  sudo pip uninstall -y virtualenv 2>/dev/null
  sudo apt-get install -y python3-virtualenv
}

if [ "$1" = on ]; then

  # Initialization moves an existing backup aside and creates a new file here.
  read_db_size on && check_backup_space "${backupPath%/*}" 1 || exit 1
  install || exit 1
  # Dependency installation can consume significant space on SYSTEM.
  read_db_size on && check_backup_space "${backupPath%/*}" 1 || exit 1

  echo "# Stop the ${netprefix}lightningd.service"
  sudo systemctl stop ${netprefix}lightningd

  # don't overwrite old backup
  if [ -f /home/bitcoin/${netprefix}lightningd.sqlite3.backup ]; then
    echo "# Backup the existing old backup on the SDcard"
    now=$(date +"%Y_%m_%d_%H%M%S")
    sudo mv /home/bitcoin/${netprefix}lightningd.sqlite3.backup \
      /home/bitcoin/${netprefix}lightningd.sqlite3.backup.${now} || exit 1
  fi

  # always re-init plugin
  if sudo ls /home/bitcoin/.lightning/${CLNETWORK}/backup.lock 2>/dev/null; then
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/backup.lock
  fi
  # https://github.com/lightningd/plugins/tree/master/backup#setup
  echo "# Initialize the backup plugin"
  cd ${plugindir}/backup/ || exit 1
  if ! sudo -u bitcoin uv run python /home/bitcoin/cl-plugins-available/plugins/backup/backup-cli init --lightning-dir /home/bitcoin/.lightning/${CLNETWORK} \
    file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup; then
    echo "# ERROR: Failed to initialize backup plugin"
    exit 1
  fi
  echo "# Backup plugin initialized successfully"

  if [ $(crontab -u admin -l | grep -c "backup-compact $CHAIN") -eq 0 ]; then
    echo "Add weekly backup-compact as a cronjob"
    cronjob="@weekly /home/admin/config.scripts/cl-plugin.backup.sh backup-compact $CHAIN"
    (
      crontab -u admin -l
      echo "$cronjob"
    ) | crontab -u admin -
  fi
  echo "# The crontab for admin now is:"
  crontab -u admin -l
  echo

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lightningd
    echo "# Started the ${netprefix}lightningd.service"
  fi

elif
  [ "$1" = off ]
then
  echo "# Removing the backup plugin"
  sudo rm -f /home/bitcoin/${netprefix}cl-plugins-enabled/backup.py
  echo "# Backup the existing old backup on the SDcard"
  now=$(date +"%Y_%m_%d_%H%M%S")
  sudo mv /home/bitcoin/${netprefix}lightningd.sqlite3.backup \
    /home/bitcoin/${netprefix}lightningd.sqlite3.backup.${now}
  echo "# Removing the backup.lock file"
  sudo rm -f /home/bitcoin/.lightning/${CLNETWORK}/backup.lock

elif
  [ "$1" = restore ]
then

  install

  #look for a backup to restore
  if sudo ls /home/bitcoin/${netprefix}lightningd.sqlite3.backup; then

    sudo systemctl stop ${netprefix}lightningd

    # https://github.com/lightningd/plugins/tree/master/backup#restoring-a-backup
    # poetry run /home/bitcoin/cl-plugins-available/plugins/backup/backup-cli restore file:///mnt/external/location ~/.lightning/bitcoin/lightningd.sqlite3

    # make sure to not overwrite old database
    if sudo ls /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3; then
      now=$(date +"%Y_%m_%d_%H%M%S")
      echo "# Backup the existing old database on the disk"
      sudo cp /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 \
        /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3.backup.${now} || exit 1
      if [ "$(echo "$@" | grep -c "force")" -gt 0 ]; then
        sudo rm /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3
      fi
    fi

    # restore
    cd ${plugindir}/backup/ || exit 1
    sudo -u bitcoin uv run python /home/bitcoin/cl-plugins-available/plugins/backup/backup-cli restore \
      file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup \
      /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3

    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      sudo systemctl start ${netprefix}lightningd
      echo "# Started the ${netprefix}lightningd.service"
    fi

  fi

elif
  [ "$1" = backup-compact ]
then
  # https://github.com/lightningd/plugins/tree/master/backup#performing-backup-compaction
  if sudo test ! -e "${backupPath}"; then
    if sudo test -L "/home/bitcoin/${netprefix}cl-plugins-enabled/backup.py" ||
      sudo test -e "${dbPath%/*}/backup.lock"; then
      echo "CLN backup is configured but its recovery file is missing: ${backupPath}" >&2
      exit 1
    fi
    echo "No active CLN file backup on ${CLNETWORK}."
    exit 0
  fi
  read_db_size backup-compact && check_backup_space "${backupPath}" 1 || exit 1
  dbSize=$(sudo du -m "${dbPath}" | awk '{print $1}')
  backupSize=$(sudo du -m "${backupPath}" | awk '{print $1}')
  if ! [[ "${dbSize}" =~ ^[0-9]+$ && "${backupSize}" =~ ^[0-9]+$ ]]; then
    echo "Cannot determine the CLN database or backup size for compaction." >&2
    exit 1
  fi
  echo "$dbSize MB $dbPath"
  echo "$backupSize MB $backupPath"
  if [ "$backupSize" -gt $((dbSize + 200)) ]; then
    # The packaged CLN service uses a private /tmp backed by /tmp. The
    # plugin holds its replay database there while writing a sibling backup.
    outputDir="${backupPath%/*}"
    outputDevice=$(sudo stat -Lc %d -- "${outputDir}") || exit 1
    tempDevice=$(sudo stat -Lc %d -- /tmp) || exit 1
    if [ "${tempDevice}" = "${outputDevice}" ]; then
      check_backup_space "${outputDir}" 2 || exit 1
    else
      check_backup_space /tmp 1 && check_backup_space "${outputDir}" 1 || exit 1
    fi
    echo "# The backup is 200MB+ larger than the db, running '${netprefix}lightning-cli backup-compact' ..."
    $lightningcli_alias backup-compact
  else
    echo "The backup is not significantly larger than the db, there is no need to compact."
  fi

else
  help
fi
