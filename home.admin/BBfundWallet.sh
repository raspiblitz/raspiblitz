#!/bin/bash
clear

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

# PRECHECK) check if chain is in sync
chainOutSync=$(lncli --chain=${network} --network=${chain}net getinfo | grep '"synced_to_chain": false' -c)
if [ ${chainOutSync} -eq 1 ]; then
  echo "FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
  echo ""
  echo "PRESS ENTER to return to menu"
  read key
  exit 1
fi

# execute command
echo "calling lncli ... please wait"
command="lncli --chain=${network} --network=${chain}net newaddress p2wkh"
echo "${command}"
result=$($command)
echo "$result"

# on no result
if [ ${#result} -eq 0 ]; then
  echo "Empty result - sorry something went wrong - thats unusual."
  echo ""
  echo "PRESS ENTER to return to menu"
  read key
  exit 1
fi
 
# parse address from result
address=$( echo "$result" | grep "address" | cut -d '"' -f4)

# prepare coin info
coininfo="Bitcoin"
if [ "$network" = "litecoin" ]; then
  coininfo="Litecoin"
fi
if [ "$chain" = "test" ]; then
  coininfo="TESTNET Bitcoin"
fi

msg="Send ${coininfo} to address --> ${address}\n\nScan the QR code on the LCD with your mobile wallet or copy paste the address.\nThe wallet you sending from needs to support bech32 addresses.\nThis screen will not update - press DONE when send."
if [ "$chain" = "test" ]; then
  msg="${msg} \n\n Get some testnet coins from https://testnet-faucet.mempool.co"
fi

echo "generating QR code ... please wait"
/home/admin/config.scripts/blitz.display.sh qr "$network:${address}"

# dialog with instructions while QR code is shown on LCD
whiptail --backtitle "Fund your on chain wallet" \
	 --title "Send ${coininfo}" \
	 --yes-button "DONE" \
	 --no-button "Console QRcode" \
	 --yesno "${msg}" 0 0

# display QR code
if [ $? -eq 1 ]; then
  /home/admin/config.scripts/blitz.display.sh qr-console "$network:${address}"
fi

# clean up
/home/admin/config.scripts/blitz.display.sh hide

# follow up info
whiptail --backtitle "Fund your on chain wallet" \
       --title "What's next?" \
       --msgbox "Wait for confirmations. \n\nYou can use info on LCD to check if funds have arrived. \n\nIf you want your lighting node to open channels automatically, activate the 'Autopilot' under 'Activate/Deactivate Services'" 0 0 