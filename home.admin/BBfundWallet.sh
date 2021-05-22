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

# LNTYPE is lnd | cln
if [ $# -gt 0 ];then
  LNTYPE=$1
else
  LNTYPE=lnd
fi

# CHAIN is signet | testnet | mainnet
if [ $# -gt 1 ];then
  CHAIN=$2
  chain=${CHAIN::-3}
else
  CHAIN=${chain}net
fi

if [ ${chain} = test ];then
  netprefix="t"
  L1rpcportmod=1
  L2rpcportmod=1
elif [ ${chain} = sig ];then
  netprefix="s"
  L1rpcportmod=3
  L2rpcportmod=3
elif [ ${chain} = main ];then
  netprefix=""
  L1rpcportmod=""
  L2rpcportmod=0
fi

lncli_alias="sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009"
bitcoincli_alias="/usr/local/bin/${network}-cli -rpcport=${L1rpcportmod}8332"
lightningcli_alias="sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/${netprefix}config"
shopt -s expand_aliases
alias lncli_alias="$lncli_alias"
alias bitcoincli_alias="$bitcoincli_alias"
alias lightningcli_alias="$lightningcli_alias"


# PRECHECK) check if chain is in sync
if [ $LNTYPE = cln ];then
  BLOCKHEIGHT=$(bitcoincli_alias getblockchaininfo|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$(lightningcli_alias getinfo | jq .blockheight)
  if [ $BLOCKHEIGHT -eq $CLHEIGHT ];then
    chainOutSync=0
  else
    chainOutSync=1
  fi
else
  chainOutSync=$(lncli_alias getinfo | grep '"synced_to_chain": false' -c)
fi
if [ ${chainOutSync} -eq 1 ]; then
  if [ $LNTYPE = cln ];then
    echo "# FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
  else
    echo "# FAIL PRECHECK - 'lightning-cli getinfo' blockheight is different from 'bitcoind getblockchaininfo' - wait until chain is sync "
  fi
  echo 
  echo "# PRESS ENTER to return to menu"
  read key
  exit 1
else
  echo "# OK - the chain is synced"
fi

# execute command
if [ $LNTYPE = cln ];then
  command="$lightningcli_alias newaddr bech32"
else
  command="$lncli_alias newaddress p2wkh"
fi
echo "# Calling:"
echo "${command}"
echo
result=$($command)
echo "$result"

# on no result
if [ ${#result} -eq 0 ]; then
  echo "# Empty result - sorry something went wrong - that is unusual."
  echo
  echo "# Press ENTER to return to menu"
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
whiptail --backtitle "Fund your onchain wallet" \
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
if [ $LNTYPE = cln ];then
  string="Wait for confirmations."
else
  string="Wait for confirmations. \n\nYou can use info on LCD to check if funds have arrived. \n\nIf you want your lighting node to open channels automatically, activate the 'Autopilot' under 'Activate/Deactivate Services'"
fi
whiptail --backtitle "Fund your onchain wallet" \
       --title "What's next?" \
       --msgbox "$string" 0 0 