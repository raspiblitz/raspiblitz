#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "tool to export macaroons & tls.cert"
 echo "lnd.export.sh [hexstring|sftp|http|btcpay] [?key-value]"

 exit 1
fi

# check if lnd is on
source <(/home/admin/_cache.sh get lnd)
if [ "${lnd}" != on ]; then
  echo "error='lnd not active'"
  exit 1
fi

# 1. parameter -> the type of export
exportType=$1

# interactive choose type of export if not set
if [ "$1" = "" ] || [ $# -eq 0 ]; then
    OPTIONS=()
    OPTIONS+=(SFTP "SSH Download (Commands)")
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
        SFTP)
          exportType='sftp';
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

  adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon)
  invoiceMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/invoice.macaroon)
  readonlyMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  restTor=$(sudo cat /mnt/hdd/tor/lndrest/hostname)

  clear
  echo "###### HEXSTRING EXPORT ######"
  echo "restTor=${restTor}:8080"
  echo ""
  echo "adminMacaroon=${adminMacaroon}"
  echo ""
  echo "invoiceMacaroon=${invoiceMacaroon}"
  echo ""
  readonlyMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  echo "readonlyMacaroon=${readonlyMacaroon}"
  echo ""
  tlsCert=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/tls.cert)
  echo "tlsCert=${tlsCert}"
  echo ""

########################
# BTCPAY Connection String
########################
elif [ "${exportType}" = "btcpay" ]; then

  # lnd needs to be unlocked
  source <(/home/admin/_cache.sh get ln_lnd_mainnet_locked)
  if [ "${ln_lnd_mainnet_locked}" == "1" ]; then
    echo "error='lnd wallet needs to be unlocked'"
    exit 1
  fi

  # take public IP as default
  # TODO: IP2TOR --> check if there is a forwarding for LND REST oe ask user to set one up
  #ip="${publicIP}"
  ip="127.0.0.1"
  port="8080"

  # will overwrite ip & port if IP2TOR tunnel is available
  source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service LND-REST-API)

  # bake macaroon that just can create invoices and monitor them
  macaroon=$(sudo -u admin lncli bakemacaroon address:read address:write info:read invoices:read invoices:write onchain:read)

  # old: admin macaroon (remove after v1.6.3 release)
  #macaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon)

  # get certificate thumb
  certthumb=$(sudo openssl x509 -noout -fingerprint -sha256 -inform pem -in /mnt/hdd/lnd/tls.cert | cut -d "=" -f 2)

  # construct connection string
  connectionString="type=lnd-rest;server=https://${ip}:${port}/;macaroon=${macaroon};certthumbprint=${certthumb}"

  if [ "$2" == "key-value" ]; then
    echo "connectionString='${connectionString}'"
    exit 1
  fi

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
# SHH / SFTP File Download
###########################
elif [ "${exportType}" = "sftp" ]; then

  local_ip=$(hostname -I | awk '{print $1}')
  clear
  echo "###### DOWNLOAD BY SFTP ######"
  echo "Copy, paste and execute these commands in your client terminal to download the files."
  echo "The password needed during download is your Password A."
  echo ""
  echo "Macaroons:"
  echo "sftp bitcoin@${local_ip}:/home/bitcoin/.lnd/data/chain/${network}/${chain}net/\*.macaroon ./"
  echo ""
  echo "TLS Certificate:"
  echo "sftp bitcoin@${local_ip}:/home/bitcoin/.lnd/tls.cert ./"
  echo ""

###########################
# HTTP File Download
###########################
elif [ "${exportType}" = "http" ]; then

  local_ip=$(hostname -I | awk '{print $1}')
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
