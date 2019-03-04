#!/bin/bash

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

command="lncli --chain=${network} --network=${chain}net newaddress np2wkh"

clear
echo "******************************"
echo "Fund your Blockchain Wallet"
echo "******************************"
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
  result=$($command)
fi

# on no result
if [ ${#result} -eq 0 ]; then
  echo "Sorry something went wrong - thats unusual."
  echo ""
  exit 1
fi
 
# when result is available
echo "$result"

# get address from result
address=$( echo "$result" | grep "address" | cut -d '"' -f4)

# prepare coin info
coininfo="REAL Bitcoin"
if [ "$network" = "litecoin" ]; then
  coininfo="REAL Litecoin"
fi
if [ "$chain" = "test" ]; then
  coininfo="TESTNET Bitcoin"
fi

msg="Send ${coininfo} to address --> ${address}\n\nScan the QR code on the LCD with your mobile wallet or copy paste the address."
if [ "$chain" = "test" ]; then
  msg="${msg} \n\n Get some testnet coins from https://testnet-faucet.mempool.co"
fi

echo -e "$network:${address}" > qr.txt
/home/admin/XXdisplayQRlcd.sh

whiptail --backtitle "Fund your on chain wallet" \
	 --title "Send ${coininfo}" \
	 --yes-button "show QR" \
	 --no-button "continue" \
	 --yesno "${msg} \n\n Do you want to see the QR-code for ${coininfo}:${address} in this window?" 0 0

if [ $? -eq 0 ]; then
    /home/admin/XXdisplayQR.sh
fi

shred qr.txt
rm -f qr.txt

whiptail --backtitle "Fund your on chain wallet" \
       --title "What's next?" \
       --msgbox "Wait for confirmations. \n\nYou can use info on LCD to check if funds have arrived. \n\nIf you want your lighting node to open channels automatically, activate the 'Autopilot' under 'Activate/Deactivate Services'" 0 0 

/home/admin/XXdisplayQRlcd_hide.sh
