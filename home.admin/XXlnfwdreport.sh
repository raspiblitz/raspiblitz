#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

# let user enter a <pubkey>@host
l1="Enter the number of days to query:"
l2="e.g. '7' will query the last 7 days"
dialog --title "Create a forwarding event report" \
--backtitle "Lightning ( ${network} | ${chain} )" \
--inputbox "$l1\n$l2" 10 60 7 2>$_temp
_input=$(cat $_temp | xargs )
shred -u $_temp
if [ ${#_input} -eq 0 ]; then
  exit 1
fi

# build command
command="lnfwdreport -n ${chain}net -c ${network} -- ${_input}"
clear
echo "Generating report..."

# execute command

result=$($command 2>$_error)
echo ""
echo ""
echo "$result"
echo ""
