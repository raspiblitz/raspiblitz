#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install and show the output of the chosen plugin for C-lightning"
  echo "Usage:"
  echo "cl-plugin.standard-python.sh on [plugin-name] [testnet|mainnet|signet] [runonce]"
  echo
  echo "tested plugins:"
  echo "summary | helpme | feeadjuster"
  echo
  echo "find more at:"
  echo "https://github.com/lightningd/plugins"
  echo
  exit 1
fi

if [ $1 = on ];then

  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

  plugin=$2

  if [ ! -f "/home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi

  if [ $($lightningcli_alias | grep -c "${plugin}") -eq 0 ];then
    echo "# Starting the ${plugin} plugin"
    sudo -u bitcoin pip install -r /home/bitcoin/cl-plugins-available/plugins/${plugin}/requirements.txt
    $lightningcli_alias plugin start /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py
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