#!/bin/bash

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

# precheck: AutoPilot
if [ "${autoPilot}" = "on" ]; then
  dialog --title 'Info' --msgbox 'You need to turn OFF the LND AutoPilot first,\nso that closed channels are not opening up again.\nYou find the AutoPilot -----> SERVICES section' 7 55
  exit 1
fi

command="lncli --chain=${network} --network=${chain}net closeallchannels --force"

clear
echo "***********************************"
echo "Closing All Channels (EXPERIMENTAL)"
echo "***********************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# PRECHECK) check if chain is in sync
chainInSync=$(lncli --chain=${network} --network=${chain}net getinfo | grep '"synced_to_chain": true' -c)
if [ ${chainInSync} -eq 0 ]; then
  command=""
  result="FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
fi

# execute command
if [ ${#command} -gt 0 ]; then
  ${command}
fi
 
echo ""
echo "OK - please recheck if channels really closed"
sleep 5
