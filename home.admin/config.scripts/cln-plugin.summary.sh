#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install and show the output if the summary plugin for C-lightning"
  echo "Usage:"
  echo "cln-plugin.summary.sh [testnet|mainnet|signet] [runonce]"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

if [ ! -f "/home/bitcoin/cln-plugins-available/plugins/summary/summary.py" ]; then
  cd /home/bitcoin || exit 1
  sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
fi
if [ $($lightningcli_alias | grep -c "summary") -eq 0 ];then
  echo "# Starting the summary plugin"
  # https://github.com/ElementsProject/lightning/tree/master/contrib/pylightning
  sudo -u bitcoin pip install pylightning 1>/dev/null
  # https://github.com/lightningd/plugins#dynamic-plugin-initialization
  sudo -u bitcoin pip install -r /home/bitcoin/cln-plugins-available/plugins/summary/requirements.txt 1>/dev/null
  $lightningcli_alias plugin start -H /home/bitcoin/cln-plugins-available/plugins/summary/summary.py 1>/dev/null
fi

echo
echo "Node URI:"
ln_getinfo=$(lightningcli_alias -H getinfo 2>/dev/null)
pubkey=$(echo "$ln_getinfo" | grep "id=" | cut -d= -f2)
toraddress=$(echo "$ln_getinfo" | grep ".onion" | cut -d= -f2)
port=$(echo "$ln_getinfo" | grep "port" | tail -n1 | cut -d= -f2)
echo "${pubkey}@${toraddress}:${port}"
echo
echo "# Running:"
echo "${netprefix}lightning-cli -H summary"
echo 
$lightningcli_alias -H summary
echo

if [ "$(echo "$@" | grep -c "runonce")" -gt 0 ];then
  $lightningcli_alias plugin stop -H /home/bitcoin/cln-plugins-available/plugins/summary/summary.py
fi