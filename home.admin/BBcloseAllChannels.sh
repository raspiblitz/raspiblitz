#!/bin/bash

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=$(cat .network); fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars $1 $2)
shopt -s expand_aliases
alias bitcoincli_alias="$bitcoincli_alias"
alias lncli_alias="$lncli_alias"
alias lightningcli_alias="$lightningcli_alias"

if [ $LNTYPE = cln ];then
  # https://lightning.readthedocs.io/lightning-close.7.html
  peerlist=$($lightningcli_alias listpeers|grep '"id":'|awk '{print $2}'|cut -d, -f1)
  # to display
  function cln_closeall_command {
    for i in $peerlist; do
      # close id [unilateraltimeout] [destination] [fee_negotiation_step] [*wrong_funding*]
      echo "$lightningcli_alias close $i 30;"
    done
  }
  command=$(cln_closeall_command)
  # to run
  function cln_closeall {
    for i in $peerlist; do
      # close id [unilateraltimeout] [destination] [fee_negotiation_step] [*wrong_funding*]
      lightningcli_alias close $i 30
    done
  }
elif [ $LNTYPE = lnd ];then
  # precheck: AutoPilot
  if [ "${autoPilot}" = "on" ]; then
    dialog --title 'Info' --msgbox 'You need to turn OFF the LND AutoPilot first,\nso that closed channels are not opening up again.\nYou find the AutoPilot -----> SERVICES section' 7 55
    exit 1
  fi
  command="$lncli_alias closeallchannels --force"
fi

clear
echo
echo "# Precheck" # PRECHECK) check if chain is in sync
if [ $LNTYPE = cln ];then
  BLOCKHEIGHT=$($bitcoincli_alias getblockchaininfo|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$($lightningcli_alias getinfo | jq .blockheight)
  if [ $BLOCKHEIGHT -eq $CLHEIGHT ];then
    chainOutSync=0
  else
    chainOutSync=1
  fi
elif [ $LNTYPE = lnd ];then
  chainOutSync=$($lncli_alias getinfo | grep '"synced_to_chain": false' -c)
fi
if [ ${chainOutSync} -eq 1 ]; then
  if [ $LNTYPE = cln ];then
    echo "# FAIL PRECHECK - '${netprefix}lightning-cli getinfo' blockheight is different from '${netprefix}bitcoind getblockchaininfo' - wait until chain is sync "
  elif [ $LNTYPE = lnd ];then
    echo "# FAIL PRECHECK - ${netprefix}lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "  
  fi
  echo 
  echo "# PRESS ENTER to return to menu"
  read key
  exit 1
else
  echo "# OK - the chain is synced"
fi

echo "#####################################"
echo "# Closing All Channels (EXPERIMENTAL)"
echo "#####################################"
echo 
echo "# COMMAND LINE: "
echo $command
echo 
echo "# RESULT:"

# execute command
if [ ${#command} -gt 0 ]; then
  if [ $LNTYPE = cln ];then
    cln_closeall
  elif [ $LNTYPE = lnd ];then  
    ${command}
  fi
fi

echo
echo "# OK - please recheck if channels really closed"
sleep 5

#TODO exits to CLI, not returning to menu