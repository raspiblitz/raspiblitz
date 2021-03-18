#!/bin/bash
clear
_temp=$(mktemp -p /dev/shm/)
_error=$(mktemp -p /dev/shm/)
sudo chmod 7777 ${_error} 2>/dev/null

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

# Check if ready (chain in sync and channels open)
./XXchainInSync.sh $network $chain
if [ $? != 0 ]; then
  exit 1
fi

# let user enter the invoice
l1="Enter the AMOUNT IN SATOSHI of the invoice:"
l2="1 ${network} = 100 000 000 SAT"
dialog --title "Pay thru Lightning Network" \
--inputbox "$l1\n$l2" 9 50 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred -u $_temp
if [ ${#amount} -eq 0 ]; then
  clear
  echo
  echo "no amount entered - returning to menu ..."
  sleep 2
  exit 1
fi

# TODO let user enter a description

# build command
command="lncli --chain=${network} --network=${chain}net addinvoice ${amount}"

# info output
clear
echo "******************************"
echo "Create Invoice / Payment Request"
echo "******************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"
sleep 2

# execute command
result=$($command 2>$_error)
error=`cat ${_error} 2>/dev/null`

#echo "result(${result})"
#echo "error(${error})"

if [ ${#error} -gt 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${error}"
else

  rhash=$(echo "$result" | grep r_hash | cut -d '"' -f4)
  payReq=$(echo "$result" | grep payment_request | cut -d '"' -f4)
  /home/admin/config.scripts/blitz.lcd.sh qr "${payReq}"

  if [ $(sudo dpkg-query -l | grep "ii  qrencode" | wc -l) = 0 ]; then
   sudo apt-get install qrencode -y > /dev/null
  fi

  echo
  echo "********************"
  echo "Here is your invoice"
  echo "********************"
  echo
  qrencode -t ANSI256 "${payReq}"
  echo
  echo "Give this Invoice/PaymentRequest to someone to pay it:"
  echo
  echo "${payReq}"
  echo
  echo "Monitoring the Incoming Payment with:"
  echo "lncli --chain=${network} --network=${chain}net lookupinvoice ${rhash}"
  echo "Press x and hold to skip to menu."

  while :
    do

    result=$(lncli --chain=${network} --network=${chain}net lookupinvoice ${rhash})
    wasPayed=$(echo $result | grep -c '"settled": true')
    if [ ${wasPayed} -gt 0 ]; then
      echo 
      echo $result
      echo
      echo "Returning to menu - OK Invoice payed."
      /home/admin/config.scripts/blitz.lcd.sh hide
      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/ok.png
      sleep 2
      break
    fi
 
    # wait 2 seconds for key input
    read -n 1 -t 2 keyPressed

    # check if user wants to abort session
    if [ "${keyPressed}" = "x" ]; then
      echo 
      echo $result
      echo
      echo "Returning to menu - invoice was not payed yet."
      break
    fi

  done

  /home/admin/config.scripts/blitz.lcd.sh hide

fi
echo "Press ENTER to return to main menu."
read key