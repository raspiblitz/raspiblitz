#!/bin/bash

function help(){
  echo
  echo "Install the backup plugin for C-lightning"
  echo "Usage:"
  echo "cln-plugin.backup.sh [on] [testnet|mainnet|signet]"
  echo "cln-plugin.backup.sh [restore] [testnet|mainnet|signet] [force]"
  echo "cln-plugin.backup.sh [backup-compact] [testnet|mainnet|signet]"
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
plugindir="/home/bitcoin/cln-plugins-available"

function install() {
  if [ ! -f "/home/bitcoin/cln-plugins-available/plugins/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cln-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi
  
  if [ $($lightningcli_alias plugin list | grep "${plugin}") -eq 0 ];then
    echo "# Starting the ${plugin} plugin"
    sudo -u bitcoin pip install --user -r ${plugindir}/${plugin}/requirements.txt
    sudo chmod +x ${plugindir}/${plugin}/${plugin}.py
    # symlink to the default plugin dir
    if [ ! -L /home/bitcoin/cln-plugins-enabled/backup ];then
      sudo ln -s /home/bitcoin/cln-plugins-available/plugins/backup /home/bitcoin/cln-plugins-enabled/
    fi
  fi
}

if [ $1 = on ];then
  
  install

  # initialize
  if [ ! -f /home/bitcoin/.lightning/${CLNETWORK}/backup.lock ];then
  # https://github.com/lightningd/plugins/tree/master/backup#setup
  /home/bitcoin/cln-plugins-enabled/backup/backup-cli init\
    --lightning-dir /home/bitcoin/.lightning/${CLNETWORK} \
    file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup
  fi


elif [ $1 = restore ];then

  install

  #look for a backup to restore
  if [ -f /home/bitcoin/${netprefix}lightningd.sqlite3.backup ];then
    
    sudo systemctl stop ${netprefix}lightningd
  
    # https://github.com/lightningd/plugins/tree/master/backup#restoring-a-backup
    # ./backup-cli restore file:///mnt/external/location ~/.lightning/bitcoin/lightningd.sqlite3
    
    # make sure to not overwrite old database
    if [ -f /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 ];then
      now=$(date +"%Y_%m_%d_%H%M%S")
      sudo cp /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3.backup.${now} || exit 1
      if [ "$(echo "$@" | grep -c "force")" -gt 0 ];then
        sudo rm /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3
      fi
    fi
  
    # restore
    /home/bitcoin/cln-plugins-enabled/backup/backup-cli restore \
      file:///home/bitcoin/${netprefix}lightningd.sqlite3.backup \
      /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3
  
    sudo systemctl start ${netprefix}lightningd
  fi

elif  [ $1 = backup-compact ];then
  
  if [ -f /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 ];then
    # https://github.com/lightningd/plugins/tree/master/backup#performing-backup-compaction
    echo "#  Running $lightning-cli backup-compact ..."
    $lightning-cli backup-compact

  else
    echo "# No /home/bitcoin/.lightning/${CLNETWORK}/lightningd.sqlite3 present"
    echo "# Run 'config.scripts/cln-plugin.backup.sh on ${CLNETWORK}' first"    
  fi

else
  help
fi