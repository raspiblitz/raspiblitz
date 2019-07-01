#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "tool to export macaroons & tls.cert"
 echo "lnd.export.sh [hexstring|scp|http|reset]"
 exit 1
fi

# 1. parameter -> the type of export
exportType=$1

# interactive choose type of export if not set
if [ "$1" = "" ] || [ $# -eq 0 ]; then
    OPTIONS=()
    OPTIONS+=(HEX "Hex-String (Copy+Paste)")
    OPTIONS+=(SCP "SSH Download (Commands)")
    OPTIONS+=(HTTP "Browserdownload (bit risky)")
    OPTIONS+=(RESET "RENEW MACAROONS & TLS")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz" \
                --title "Export Macaroons & TLS.cert" \
                --menu "How do you want to export?" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        HEX)
          exportType='hexstring';
          ;;
        SCP)
          exportType='scp';
          ;;
        HTTP)
          exportType='http';
          ;;
        RESET)
          exportType='reset';
          ;;
    esac
fi

# load data from config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

########################
# CANCEL
########################
if [ ${#exportType} -eq 0 ]; then

  echo "CANCEL"
  exit 0

########################
# HEXSTRING
########################
elif [ "${exportType}" = "hexstring" ]; then

  clear
  echo "###### HEXSTRING EXPORT ######"
  echo ""
  echo "admin.macaroon:"
  sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon
  echo ""
  echo "invoice.macaroon:"
  sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/invoice.macaroon
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
elif [ "${exportType}" = "scp" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  clear
  echo "###### DOWNLOAD BY SCP ######"
  echo "Copy, paste and execute these commands in your client terminal to download the files."
  echo "The password needed during download is your Password A."
  echo ""
  echo "admin.macaroon:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon ./"
  echo ""
  echo "invoice.macaroon:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/invoice.macaroon ./"
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
elif [ "${exportType}" = "http" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  randomPortNumber=$(shuf -i 20000-39999 -n 1)
  sudo ufw allow from 192.168.0.0/16 to any port ${randomPortNumber} comment 'temp http server'
  clear
  echo "###### DOWNLOAD BY HTTP ######"
  echo ""
  echo "Open in your browser --> http://${local_ip}:${randomPortNumber}"
  echo ""
  echo "You need to be on the same local network - not reachable from outside."
  echo "In browser click on files or use 'save as' from context menu to download."
  echo ""
  echo "Temp HTTP Server is running - use CTRL+C to stop when you are done"
  echo ""
  cd 
  randomFolderName=$(shuf -i 100000000-900000000 -n 1)
  mkdir ${randomFolderName}
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon ./${randomFolderName}/admin.macaroon
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/readonly.macaroon ./${randomFolderName}/readonly.macaroon
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/invoice.macaroon ./${randomFolderName}/invoice.macaroon
  sudo cp /home/bitcoin/.lnd/tls.cert ./${randomFolderName}/tls.cert
  cd ${randomFolderName}
  sudo chmod 444 *.*
  python -m SimpleHTTPServer ${randomPortNumber} 2>/dev/null
  sudo ufw delete allow from 192.168.0.0/16 to any port ${randomPortNumber} comment 'temp http server'
  cd ..
  sudo rm -r ${randomFolderName}
  echo "OK - temp HTTP server is stopped."

###########################
# RESET Macaroons and TLS
###########################
elif [ "${exportType}" = "reset" ]; then

  clear
  echo "###### RESET MACAROONS AND TLS.cert ######"
  echo ""
  echo "All your macaroons and the tls.cert get deleted and recreated."
  echo "Use this to invalidate former EXPORTS for example if you loose a device."
  echo ""
  cd
  echo "- deleting old macaroons"
  sudo rm /home/admin/.lnd/data/chain/${network}/${chain}net/*.macaroon
  sudo rm /home/bitcoin/.lnd/data/chain/${network}/${chain}net/*.macaroon
  sudo rm /home/bitcoin/.lnd/data/chain/${network}/${chain}net/macaroons.db
  echo "- resetting TLS cert"
  sudo /home/admin/config.scripts/lnd.newtlscert.sh
  echo "- restarting LND ... wait 10 secs"
  sudo systemctl start lnd
  sleep 10
  sudo -u bitcoin lncli --chain=${network} --network=${chain}net unlock
  echo "- creating new macaroons ... wait 10 secs"
  sleep 10
  echo "- copy new macaroons to admin user"
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/*.macaroon /home/admin/.lnd/data/chain/${network}/${chain}net/
  sudo chown admin:admin -R /home/admin/.lnd/data/chain/${network}/${chain}net/*.macaroon
  echo "OK DONE"

else
  echo "FAIL: unknown '${exportType}' -run-> ./lnd.export.sh -h"
fi