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
pinnedVersion="46f28a88a2aa15c7c1b3c95a21dd99ea2195995e"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  help
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

plugin="backup"
plugindir="/home/bitcoin/cl-plugins-available/plugins"

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
    # upgrade pip
    sudo pip3 config set global.break-system-packages true
    sudo pip3 install --upgrade pip

    # pip dependencies
    sudo -u bitcoin pip3 config set global.break-system-packages true
    sudo -u bitcoin pip3 install pyln-client tqdm psutil

    # poetry
    sudo pip3 install poetry || exit 1
    cd ${plugindir}/backup/ || exit 1
    sudo -u bitcoin poetry install

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

  install

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
  sudo -u bitcoin poetry run /home/bitcoin/cl-plugins-available/plugins/backup/backup-cli init --lightning-dir /home/bitcoin/.lightning/${CLNETWORK} \
    file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup

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
    sudo -u bitcoin poetry run /home/bitcoin/cl-plugins-available/plugins/backup/backup-cli restore \
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
  dbPath="/home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3"
  backupPath="/home/bitcoin/${netprefix}lightningd.sqlite3.backup"

  if sudo ls "${dbPath}" >/dev/null; then
    dbSize=$(sudo du -m "${dbPath}" | awk '{print $1}')
    echo "$dbSize MB $dbPath"
    backupSize=$(sudo du -m "${backupPath}" | awk '{print $1}')
    echo "$backupSize MB $backupPath"
    if [ "$backupSize" -gt $((dbSize + 200)) ]; then
      echo "# The backup is 200MB+ larger than the db, running '${netprefix}lightning-cli backup-compact' ..."
      $lightningcli_alias backup-compact
    else
      echo "The backup is not significantly larger than the db, there is no need to compact."
    fi
  else
    echo "# No ${dbPath} is present"
    echo "# Run 'config.scripts/cl-plugin.backup.sh on ${CLNETWORK}' first"
  fi

else
  help
fi
