#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "tool to export macaroons & tls.cert"
 echo "lnd.export.sh [hexstring|scp|http|btcpay]"
 exit 1
fi

# 1. parameter -> the type of export
exportType=$1

# interactive choose type of export if not set
if [ "$1" = "" ] || [ $# -eq 0 ]; then
    OPTIONS=()
    OPTIONS+=(SCP "SSH Download (Commands)")
    OPTIONS+=(HTTP "Browserdownload (bit risky)")
    OPTIONS+=(HEX "Hex-String (Copy+Paste)")   
    OPTIONS+=(STR "BTCPay Connection String") 
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
        STR)
          exportType='btcpay';
          ;;
        SCP)
          exportType='scp';
          ;;
        HTTP)
          exportType='http';
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

########################
# BTCPAY Connection String
########################
elif [ "${exportType}" = "btcpay" ]; then

  # take public IP as default
  # TODO: IP2TOR --> check if there is a forwarding for LND REST oe ask user to set one up
  #ip="${publicIP}"
  ip="127.0.0.1"
  port="8080"

  # will overwrite ip & port if IP2TOR tunnel is available
  source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service LND-REST-API)

  # check if there is a IP2TOR for LND REST

  # get macaroon
  # TODO: best would be not to use admin macaroon here in the future
  macaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon)

  # get certificate thumb
  certthumb=$(sudo openssl x509 -noout -fingerprint -sha256 -inform pem -in /mnt/hdd/lnd/tls.cert | cut -d "=" -f 2)

  # construct connection string
  connectionString="type=lnd-rest;server=https://${ip}:${port}/;macaroon=${macaroon};certthumbprint=${certthumb}"

  clear
  echo "###### BTCPAY CONNECTION STRING ######"
  echo ""
  echo "${connectionString}"
  echo ""

  # add info about outside reachability (type would have a value if IP2TOR tunnel was found)
  if [ ${#type} -gt 0 ]; then
    echo "NOTE: You have a IP2TOR connection for LND REST API .. so you can use this connection string also with a external BTCPay server."
  else
    echo "IMPORTANT: You can only use this connection string for a BTCPay server running on this RaspiBlitz."
    echo "If you want to connect from a external BTCPay server activate a IP2TOR tunnel for LND-REST first:"
    echo "MAIN MENU > SUBSCRIBE > IP2TOR > LND REST API"
    echo "Then come back and get a new connection string."
  fi
  echo ""

###########################
# SHH / SCP File Download
###########################
elif [ "${exportType}" = "scp" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  clear
  echo "###### DOWNLOAD BY SCP ######"
  echo "Copy, paste and execute these commands in your client terminal to download the files."
  echo "The password needed during download is your Password A."
  echo ""
  echo "Macaroons:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/\*.macaroon ./"
  echo ""
  echo "TLS Certificate:"
  echo "scp bitcoin@${local_ip}:/home/bitcoin/.lnd/tls.cert ./"
  echo ""

###########################
# HTTP File Download
###########################
elif [ "${exportType}" = "http" ]; then

  local_ip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
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
  python3 -m http.server ${randomPortNumber} 2>/dev/null
  sudo ufw delete allow from 192.168.0.0/16 to any port ${randomPortNumber} comment 'temp http server'
  cd ..
  sudo rm -r ${randomFolderName}
  echo "OK - temp HTTP server is stopped."

else
  echo "FAIL: unknown '${exportType}' - run with -h for help"
fi

if [ "$1" = "" ] || [ $# -eq 0 ]; then
  echo "Press ENTER to return to main menu."
  read key
fi
