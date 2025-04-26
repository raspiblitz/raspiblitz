#!/bin/bash

# https://github.com/getAlby/lightning-browser-extension

# command info
echo "config script to connect to Alby - The Bitcoin Lightning App for your Browser"


# 1. TOR or IP (optional - default IP)
forceTOR=0
if [ "$1" == "tor" ]; then
  forceTOR=1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/app-data/raspiblitz.conf

# generate data parts
hex_macaroon=$(sudo xxd -plain /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon | tr -d '\n')
cert=$(sudo grep -v 'CERTIFICATE' /mnt/hdd/app-data/lnd/tls.cert | tr -d '=' | tr '/+' '_-' | tr -d '\n')

#### ADAPT PARAMETERS BASED RASPIBLITZ CONFIG

# get the local IP as default host
if [ ${#host} -eq 0 ]; then
    host=$(hostname -I | awk '{print $1}')
fi

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  host="${dynDomain}"
fi

# make sure lnd rest tor service is active when tor is active
tor_host=$(sudo cat /mnt/hdd/app-data/tor/lndrest/hostname)
if [ "${runBehindTor}" == "on" ] && [ "${tor_host}" == "" ]; then
  /home/admin/config.scripts/tor.onion-service.sh lndrest 8080 8080
  tor_host=$(sudo cat /mnt/hdd/app-data/tor/lndrest/hostname)
fi

# tunnel thru TOR if running and supported by the wallet
if [ ${forceTOR} -eq 1 ]; then
  host=$tor_host
  if [ "${host}" == "" ]; then
    echo "# setting up onion service ..."
    /home/admin/config.scripts/tor.onion-service.sh lndrest 8080 8080
    host=$(sudo cat /mnt/hdd/app-data/tor/lndrest/hostname)
  fi
fi

# tunnel thru SSH-Reverse-Tunnel if activated for that port
if [ ${#sshtunnel} -gt 0 ]; then
  isForwarded=$(echo ${sshtunnel} | grep -c "${port}<")
  if [ ${isForwarded} -gt 0 ]; then
    if [ "${port}" == "10009" ]; then
      host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1 | cut -d ':' -f1)
      port=$(echo $sshtunnel | awk '{split($0,a,"10009<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
      echo "# using ssh-tunnel --> host ${host} port ${port}"
    elif [ "${port}" == "8080" ]; then
      host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1 | cut -d ':' -f1)
      port=$(echo $sshtunnel | awk '{split($0,a,"8080<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
      echo "# using ssh-tunnel --> host ${host} port ${port}"
    fi
  fi
fi

echo
whiptail --title " Alby - The Lightning App for your Browser" --msgbox "Visit https://getAlby.com and install Alby for your browser.

Then open Alby and add a new lightning account.

Select RaspiBlitz.

Your RaspiBlitz connection details for Alby will be shown on the next screen.

" 16 67

clear

echo "---------------------------------------------------"
echo "Use the following connection details in Alby:"
echo ""
echo "# REST API host:"
echo "https://${host}:8080"
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  echo "# Make sure you are on the same local network (WLAN same as LAN - use WIFI not cell network on phone)."
fi
if [ ${#usingIP2TOR} -gt 0 ] && [ ${forceTOR} -eq 0 ]; then
  echo "Your IP2TOR bridge '${usingIP2TOR}' is used for this connection."
fi
if [ "${host}" != "${tor_host}" ]; then
  if [ "${tor_host}" != "" ]; then
    echo "# Alternatively you can also connect through Tor:"
    echo "https://${tor_host}:8080"
  fi
fi

echo ""
echo "# Macaroon (HEX format)"
echo "${hex_macaroon}"
echo "# Note: these are your admin credentials"


echo ""
echo "Press ENTER to return to main menu."
read key
clear
