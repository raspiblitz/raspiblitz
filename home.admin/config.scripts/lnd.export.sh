#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ] || [ $# -eq 0 ]; then
 echo "tool to export macaroons & tls.cert"
 echo "lnd.export.sh [hexstring|scp|http]"
 exit 1
fi

# load data from config
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# 1. parameter -> the type of export
exportType=$1

########################
# HEXSTRING
########################
if [ ${exportType} = "hexstring" ]; then

  clear
  echo "###### HEXSTRING EXPORT ######"
  echo ""
  echo "admin.macaroon:"
  sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon
  echo ""
  echo "readonly.macaroon:"
  sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/readonly.macaroon
  echo ""
  echo "tls.cert:"
  sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/tls.cert
  echo ""

###########################
# SHH / SCP File Download
###########################
elif [ ${exportType} = "scp" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  clear
  echo "###### DOWNLOAD BY SCP ######"
  echo "Copy, past and execute these commands in your client terminal to download the files."
  echo "The password needed during download is your Password A."
  echo ""
  echo "admin.macaroon:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon ./"
  echo ""
  echo "readonly.macaroon:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/readonly.macaroon ./"
  echo ""
  echo "tls.cert:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/tls.cert ./"
  echo ""

###########################
# HTTP File Download
###########################
elif [ ${exportType} = "http" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  randomPortNumber=$(shuf -i 20000-39999 -n 1)
  clear
  echo "###### DOWNLOAD BY HTTP ######"
  echo ""
  echo "Open in your browser --> http://${local_ip}:${randomPortNumber}"
  echo "You need to be on the same local network - not reachable from outside."
  echo "In browser click on files or use 'save as' from context menu to download."
  echo ""
  echo "Temp HTTP Server is running - use CTRL+C to stop when you are done"
  cd 
  randomFolderName=$(shuf -i 100000000-900000000 -n 1)
  mkdir ${randomFolderName}
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon ./${randomFolderName}/admin.macaroon
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/readonly.macaroon ./${randomFolderName}/readonly.macaroon
  sudo cp /home/bitcoin/.lnd/tls.cert ./${randomFolderName}/tls.cert
  cd ${randomFolderName}
  sudo ufw allow from 192.168.0.0/24 to any port ${randomPortNumber} comment 'temp http server'
  python -m SimpleHTTPServer ${randomPortNumber}
  sudo ufw delete allow from 192.168.0.0/24 to any port ${randomPortNumber} comment 'temp http server'
  cd ..
  sudo rm -r ${randomFolderName}
  echo "OK - temp HTTP server is stopped."

else
  echo "FAIL: unknown '${exportType}' -run-> ./lnd.export.sh -h"
fi