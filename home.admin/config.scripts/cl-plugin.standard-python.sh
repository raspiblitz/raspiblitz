#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install and show the output of the chosen plugin for C-lightning"
  echo "Usage:"
  echo "cl-plugin.standard-python.sh on [plugin-name] <testnet|mainnet|signet> <persist|runonce>"
  echo
  echo "tested plugins:"
  echo "summary | helpme | feeadjuster | paytest"
  echo
  echo "find more at:"
  echo "https://github.com/lightningd/plugins"
  echo
  exit 1
fi

if [ "$1" = "on" ];then

  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $3)

  plugin=$2

  # download
  if [ ! -f "/home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi

  # enable
  if [ "$(echo "$@" | grep -c "persist")" -gt 0 ];then
    if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py ];then
      echo "# Symlink to /home/bitcoin/${netprefix}cl-plugins-enabled"
      sudo ln -s /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py \
                 /home/bitcoin/${netprefix}cl-plugins-enabled
      
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" == "ready" ]; then
        echo "# Restart the ${netprefix}lightningd.service to activate the ${plugin} plugin"
        sudo systemctl restart ${netprefix}lightningd
      fi
    fi
  
  else
    if [ $($lightningcli_alias | grep -c "${plugin}") -eq 0 ];then
      echo "# Just start the ${plugin} plugin"
      sudo -u bitcoin pip install -r /home/bitcoin/cl-plugins-available/plugins/${plugin}/requirements.txt
      $lightningcli_alias plugin start /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py
    fi
  fi
  
  echo
  echo "Node URI:"
  ln_getinfo=$($lightningcli_alias -H getinfo 2>/dev/null)
  pubkey=$(echo "$ln_getinfo" | grep "id=" | cut -d= -f2)
  toraddress=$(echo "$ln_getinfo" | grep ".onion" | cut -d= -f2)
  port=$(echo "$ln_getinfo" | grep "port" | tail -n1 | cut -d= -f2)
  echo "${pubkey}@${toraddress}:${port}"
  echo
  echo "# Running:"
  echo "${netprefix}lightning-cli ${plugin}"
  echo 
  $lightningcli_alias ${plugin}
  echo

  if [ "$(echo "$@" | grep -c "runonce")" -gt 0 ];then
    $lightningcli_alias plugin stop /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py
  fi

fi