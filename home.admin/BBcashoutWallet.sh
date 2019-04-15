#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

echo "please wait ..."

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')
fi

# check if user has money in lightning channels - info about close all
openChannels=$(lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | jq '.[] | length')
if [ ${#openChannels} -eq 0 ]; then
  clear
  echo "*** IMPORTANT **********************************"
  echo "It looks like LND is not responding."
  echo "Still starting up, is locked or is not running?"
  echo "Try later, try reboot or check ./XXdebugLogs.sh"
  echo "************************************************"
  exit 1
fi

if [ ${openChannels} -gt 0 ]; then
   whiptail --title 'Info' --yes-button='Cashout Anyway' --no-button='Go Back' --yesno 'You still have funds in open Lightning Channels.\nUse CLOSEALL first if you want to cashout all funds.\nNOTICE: Just confirmed on-chain funds can be moved' 10 56
   if [ $? -eq 1 ]; then
     exit 1
   fi
   echo "please wait ..."
   exit 1
fi

# check if money is waiting to get confirmed
unconfirmed=$(lncli --chain=${network} --network=${chain}net walletbalance | grep '"unconfirmed_balance"' | cut -d '"' -f4)
if [ ${unconfirmed} -gt 0 ]; then
   dialog --title 'Info' --msgbox "Still waiting confirmation for ${unconfirmed} sat.\nNOTICE: Just confirmed on-chain funds can be moved." 6 58
   if [ $? -eq 1 ]; then
     exit 1
   fi
   echo "please wait ..."
   exit 1
fi

# get available amount in on-chain wallet
maxAmount=$(lncli --chain=${network} --network=${chain}net walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
if [ ${maxAmount} -eq 0 ]; then
   dialog --title 'Info' --msgbox "You have 0 moveable funds available.\nNOTICE: Just confirmed on-chain funds can be moved." 6 58
   exit 1
fi

# let user enter the address
l1="Enter on-chain address to send confirmed funds to:"
#l2="You will send: ${maxAmount} sat"
#l3="Maximal fee: 20000 sat (wil be subtracted)"
dialog --title "Where to send funds?" \
--inputbox "\n$l1\n" 9 75 2>$_temp
if test $? -eq 0
then
   echo "ok pressed"
else
   echo "cancel pressed"
   exit 1
fi
address=$(cat $_temp | xargs)
shred $_temp
if [ ${#address} -eq 0 ]; then
  echo "FAIL - not a valid address (${address})"
  exit 1
fi

clear
echo "******************************"
echo "Send on-chain Funds"
echo "******************************"

# execute command
command="lncli --chain=${network} --network=${chain}net sendcoins --sweepall --addr=${address} --conf_target=3"
echo "$command"
result=$($command 2>$_error)
error=`cat ${_error}`
    
if [ ${#result} -eq 0 ]; then
  # fail - retry on 'insufficient funds available to construct transaction'
  echo "FAIL: $error"
  tryAgain=$(echo "${error}" | grep -c 'insufficient funds available to construct transaction')
  if [ ${tryAgain} -eq 0 ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "FINAL FAIL --> Was not able to send transaction (see error above)"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  else
    # success
    echo "$result"
    echo ""
    echo "********************************************************************"
    echo "OK --> to address ${address}"
    echo "********************************************************************"    
  fi
echo ""
