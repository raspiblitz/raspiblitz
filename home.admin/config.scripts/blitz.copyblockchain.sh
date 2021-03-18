#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the copy of blockchain data over LAN"
 echo "# blitz.copyblockchain.sh [status]"
 echo "error='missing parameters'"
 exit 1
fi

# load basic system settings
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# check that blockchain is set & supported
if [ "${network}" != "bitcoin" ] && [ "${network}" != "litecoin" ]; then
  echo "blockchain='{$network}'"
  echo "error='blockchain type missing or not supported'"
  exit 1
fi

# check that HDD is available
isMounted=$(sudo df | grep -c /mnt/hdd)
if [ "${isMounted}" != "1" ]; then
  echo "error='no datadrive is mounted'"
  exit 1
fi

###################
# STATUS
###################

# check if copy is in progress
copyBeginTime=$(cat /mnt/hdd/${network}/copy_begin.time 2>/dev/null | tr -cd '[[:digit:]]')
if [ ${#copyBeginTime} -eq 0 ]; then
  copyBeginTime=0
fi
copyEndTime=$(cat /mnt/hdd/${network}/copy_end.time 2>/dev/null | tr -cd '[[:digit:]]')
if [ ${#copyEndTime} -eq 0 ]; then
  copyEndTime=0
fi
copyInProgress=0
if [ ${copyBeginTime} -gt ${copyEndTime} ]; then
  copyInProgress=1
fi

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# blitz.copyblockchain.sh"
  echo "copyInProgress=${copyInProgress}"
  echo "copyBeginTime=${copyBeginTime}"
  echo "copyEndTime=${copyEndTime}"
  exit 1
fi

# if no other 
echo "error='unknown command'"
exit 1
