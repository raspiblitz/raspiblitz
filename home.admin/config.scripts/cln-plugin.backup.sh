#!/bin/bash

function help(){
  echo
  echo "Install the backup plugin for C-lightning"
  echo "Replicates the lightningd.sqlite3 database on the SDcard"
  echo
  echo "Usage:"
  echo "cln-plugin.backup.sh [on|off] [testnet|mainnet|signet]"
  echo "cln-plugin.backup.sh [restore] [testnet|mainnet|signet] [force]"
  echo "cln-plugin.backup.sh [backup-compact] [testnet|mainnet|signet]"
  echo "cln-plugin.backup.sh [check [testnet|mainnet|signet]"
  echo
  echo "https://github.com/lightningd/plugins/tree/master/backup"
  echo
  exit 1
}

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  help
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

plugin="backup"
plugindir="/home/bitcoin/cln-plugins-available/plugins"

function install() {
  if [ ! -f "${plugindir}/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cln-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi
  
  if [ $($lightningcli_alias plugin list 2>/dev/null | grep -c "${plugin}") -eq 0 ];then
    echo "# Checking dependencies"
    sudo -u bitcoin pip install --user -r ${plugindir}/${plugin}/requirements.txt 1>/dev/null
      if [ $(echo $PATH | grep -c "/home/bitcoin/.local/bin") -eq 0 ];then
        export PATH=$PATH:/home/bitcoin/.local/bin
        echo "PATH=\$PATH:/home/bitcoin/.local/bin" | sudo tee -a /etc/profile
      fi
    sudo chmod +x ${plugindir}/${plugin}/${plugin}.py
    # symlink to the default plugin dir
    if [ ! -L /home/bitcoin/${netprefix}cln-plugins-enabled/backup.py ];then
      sudo ln -s ${plugindir}/backup/backup.py \
                 /home/bitcoin/${netprefix}cln-plugins-enabled/
    fi
  else
    echo "# The ${plugin} plugin is already loaded"
  fi
}

if [ $1 = on ];then
  
  install

  echo "# Stop the ${netprefix}lightningd.service"
  sudo systemctl stop ${netprefix}lightningd
  
  # don't overwrite old backup
  if [ -f /home/bitcoin/${netprefix}lightningd.sqlite3.backup ];then
    echo "# Backup the existing old backup on the SDcard"
    now=$(date +"%Y_%m_%d_%H%M%S")
    sudo mv /home/bitcoin/${netprefix}lightningd.sqlite3.backup \
            /home/bitcoin/${netprefix}lightningd.sqlite3.backup.${now} || exit 1
  fi

  # init plugin
  if ! sudo ls /home/bitcoin/.lightning/${CLNETWORK}/backup.lock; then
    # https://github.com/lightningd/plugins/tree/master/backup#setup
    echo "# Initialize the backup plugin"
    sudo -u bitcoin ${plugindir}/backup/backup-cli init\
      --lightning-dir /home/bitcoin/.lightning/${CLNETWORK} \
      file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup
  fi

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lightningd
    echo "# Started the ${netprefix}lightningd.service"
  fi

elif [ $1 = check ];then



elif [ $1 = off ];then
  echo "# Removing the backup plugin"
  sudo rm -f /home/bitcoin/${netprefix}cln-plugins-enabled/backup.py
  echo "# Backup the existing old backup on the SDcard"
  now=$(date +"%Y_%m_%d_%H%M%S")
  sudo mv /home/bitcoin/${netprefix}lightningd.sqlite3.backup \
            /home/bitcoin/${netprefix}lightningd.sqlite3.backup.${now}
  echo "# Removing the backup.lock file"
  sudo rm -f  /home/bitcoin/.lightning/${CLNETWORK}/backup.lock

elif [ $1 = restore ];then

  install

  #look for a backup to restore
  if sudo ls /home/bitcoin/${netprefix}lightningd.sqlite3.backup; then
    
    sudo systemctl stop ${netprefix}lightningd
  
    # https://github.com/lightningd/plugins/tree/master/backup#restoring-a-backup
    # ./backup-cli restore file:///mnt/external/location ~/.lightning/bitcoin/lightningd.sqlite3
    
    # make sure to not overwrite old database
    if sudo ls /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3;then
      now=$(date +"%Y_%m_%d_%H%M%S")
      echo "# Backup the existing old database on the disk"
      sudo cp /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 \
              /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3.backup.${now} || exit 1
      if [ "$(echo "$@" | grep -c "force")" -gt 0 ];then
        sudo rm /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3
      fi
    fi
  
    # restore
    sudo -u bitcoin ${plugindir}/backup/backup-cli restore \
      file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup \
      /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3
  
    sudo systemctl start ${netprefix}lightningd
  fi

elif [ $1 = backup-compact ];then
  
  if sudo ls /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3;then
    # https://github.com/lightningd/plugins/tree/master/backup#performing-backup-compaction
    echo "#  Running $lightning-cli backup-compact ..."
    $lightningcli_alias backup-compact

  else
    echo "# No /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 is present"
    echo "# Run 'config.scripts/cln-plugin.backup.sh on ${CLNETWORK}' first"    
  fi

else
  help
fi