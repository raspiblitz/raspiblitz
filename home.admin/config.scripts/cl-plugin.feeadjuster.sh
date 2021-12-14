#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the feeadjuster plugin for C-lightning"
  echo "Usage:"
  echo "cl-plugin.feeadjuster.sh [on|off] <testnet|mainnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

if [ "$1" = "on" ];then

  plugin="feeadjuster"
  if [ ! -f "/home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py" ]; then
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
    sudo -u bitcoin pip install -r /home/bitcoin/cl-plugins-available/plugins/${plugin}/requirements.txt
  fi
  if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py ];then
    sudo ln -s /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py \
               /home/bitcoin/${netprefix}cl-plugins-enabled
    sudo chmod +x /home/bitcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ] && [ "$3" != "norestart" ]; then
    echo "# Start ${netprefix}${plugin}"
    $lightningcli_alias plugin start /home/bitcoin/cl-plugins-enabled/${plugin}.py
  fi

fi

if [ "$1" = "off" ];then

  echo "Stop the ${plugin}"
  $lightningcli_alias plugin stop home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py

  echo "# delete symlink"
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py
  
  echo "# Edit ${CLCONF}"
  sudo sed -i "/^feeadjuster/d" ${CLCONF}

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "off"

  echo "# The ${plugin} was uninstalled"
fi