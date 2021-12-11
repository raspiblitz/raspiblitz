#!/bin/bash
trap 'rm -f "$_temp"' EXIT
trap 'rm -f "$_error"' EXIT
_temp=$(mktemp -p /dev/shm/)
_error=$(mktemp -p /dev/shm/)

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=$(cat .network); fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars $1 $2)

# raise high focus on lightning peers next 5min
/home/admin/_cache.sh focus ln_${LNTYPE}_${$CHAIN}_peers 0 300

# let user enter a <pubkey>@host
l1="Enter the node pubkey address with host information:"
l2="example -----> 024ddf33[...]1f5f9f3@91.65.1.38:9735"
if [ "$chain" = "main" ]; then
  l3="node directory -> https://1ml.com"
elif [ "$chain" = "test" ]; then
    l3="node directory -> https://1ml.com/testnet"
fi
dialog --title "Open a Connection to a Peer" \
--backtitle "Lightning ( ${network} | ${chain} )" \
--inputbox "$l1\n$l2\n$l3" 10 60 2>$_temp
_input=$(cat $_temp | xargs )
shred -u $_temp
if [ ${#_input} -eq 0 ]; then
  clear
  echo
  echo "no peer entered - returning to menu ..."
  sleep 2
  exit 0
fi

pubkey=$(echo "${_input}"|cut -d@ -f1)
# address=$(echo "${_input}"|cut -d@ -f2|cut -d: -f1)
# port=$(echo "${_input}"|cut -d: -f2)
# build command
if [ $LNTYPE = cl ];then
  # connect id [host port]
  command="$lightningcli_alias connect ${_input}"
elif [ $LNTYPE = lnd ];then
  command="$lncli_alias connect ${_input}"
fi

# info output
clear
echo "******************************"
echo "Connect to a Lightning Node"
echo "******************************"
echo
echo "COMMAND LINE: "
echo $command
echo
echo "RESULT (might have to wait for timeout):"

win=1
info=""

# check if input is available
if [ ${#_input} -lt 10 ]; then
  win=0
  info="node pubkey@host info is too short"
elif [ $LNTYPE = lnd ];then
  gotAt=$(echo $_input | grep '@' -c)
  if [ ${gotAt} -eq 0 ]; then
    win=0
    info="format is not pubkey@host - @ is missing"
  fi
fi

# execute command
sleep 2
result="$info"
if [ ${win} -eq 1 ]; then
  result=$($command 2>$_error)
fi

# on no result
if [ ${#result} -eq 0 ]; then

  # basic error
  win=0
  info="No return value. Error not known."

  # try to get error output
  result=$(cat "${_error}")
  echo "$result"

  # basic cli error
  cliError=$(echo "${result}" | grep "[lncli]" -c )
  if [ ${cliError} -gt 0 ]; then
    info="It's possible that the lightning daemon is not running, not configured correct or not connected to the cli."
  fi

else

  # when result is available
  echo "$result"

  # check if the node is now in peer list
  if [ $LNTYPE = cl ];then
    isPeer=$($lightningcli_alias listpeers 2>/dev/null| grep "${pubkey}" -c)
  elif [ $LNTYPE = lnd ];then
    isPeer=$($lncli_alias listpeers 2>/dev/null| grep "${pubkey}" -c)
  fi
  if [ ${isPeer} -eq 0 ]; then

    # basic error message
    win=0
    info="Was not able to establish connection to node."

    # TODO: try to find out more details from cli output

  else
    win=1
    info="Perfect - a connection to that node got established :)"
  fi

fi

# output info
echo
if [ ${win} -eq 1 ]; then
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "${info}"
  echo
  echo "What's next? --> Open a channel with that node."
else
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${info}"
fi

echo
echo "Press ENTER to return to main menu."
read key