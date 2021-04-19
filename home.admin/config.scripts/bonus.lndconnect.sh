#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to connect mobile apps with lnd connect"
 echo "# will autodetect dyndns, sshtunnel or TOR"
 echo "# bonus.lndconnect.sh [zap-ios|zap-android|zeus-ios|zeus-android|shango-ios|shango-android|sendmany-android] [?ip|tor]"
 exit 1
fi

# make sure commandline tool is available
sudo apt-get install -y qrencode 1>/dev/null 2>/dev/null

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

#### PARAMETER

# 1. TARGET WALLET
targetWallet=$1

# 1. TOR or IP (optional - default IP)
forceTOR=0
if [ "$2" == "tor" ]; then
  forceTOR=1
fi

#### CHECK IF IP2TOR BRIDGES ARE AVAILABLE
ip2torREST_IP=""
ip2torREST_PORT=""
error=""
source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service LND-REST-API)
if [ ${#error} -eq 0 ]; then
  ip2torREST_IP="${ip}"
  ip2torREST_PORT="${port}"
fi
ip2torGRPC_IP=""
ip2torGRPC_PORT=""
error=""
source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service LND-GRPC-API)
if [ ${#error} -eq 0 ]; then
  ip2torGRPC_IP="${ip}"
  ip2torGRPC_PORT="${port}"
fi

#### ADAPT PARAMETERS BASED TARGETWALLET 

# defaults
host=""
port=""
addcert=1
supportsTOR=0
usingIP2TOR=""
connectInfo="When you start the App choose to connect to your own node.\n(DIY / Remote-Node / lndconnect)\nClick on the 'Scan QR' button."

if [ "${targetWallet}" = "zap-ios" ]; then
  if [ ${forceTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses REST
    port="8080"
    addcert=0
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  
  
elif [ "${targetWallet}" = "zap-android" ]; then
  connectInfo="- start the Zap Wallet --> SETUP WALLET\n  or choose new Wallet in app menu\n- scan the QR code \n- confirm host address"
  if [ ${forceTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses gRPC
    port="10009"
    connectInfo="${connectInfo}\n- install & connect Orbot App (VPN mode)"
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=1
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi 

elif [ "${targetWallet}" = "zeus-ios" ]; then

    port="8080"
    usingIP2TOR="LND-REST-API"
    forceTOR=1
    host=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
    connectInfo="- start the Zeus Wallet --> lndconnect\n- scan the QR code \n- activate 'Tor' option \n- activate 'Certification Verification' option\n- save Node Config"

elif [ "${targetWallet}" = "zeus-android" ]; then

    port="8080"
    usingIP2TOR="LND-REST-API"
    forceTOR=1
    host=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
    connectInfo="- start the Zeus Wallet --> lndconnect\n- scan the QR code \n- activate 'Tor' option \n- activate 'Certification Verification' option\n- save Node Config"

elif [ "${targetWallet}" = "sendmany-android" ]; then

  connector="lndconnect"
  if [ ${forceTOR} -eq 1 ]; then
    # echo "error='no tor support'"
    # exit 1
    # port="8080"
    # addcert=0
    # deactivate TOR for now, because address is too long QR code is too big to be scanned by
    # app and so just make it possible to use local.
    forceTOR=0
  fi
  port="10009"
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  

else
  echo "error='unknown target wallet'"
  exit 1
fi

#### ADAPT PARAMETERS BASED RASPIBLITZ CONFIG

# get the local IP as default host
if [ ${#host} -eq 0 ]; then
    host=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
fi

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  host="${dynDomain}"
fi

# tunnel thru TOR if running and supported by the wallet
if [ ${forceTOR} -eq 1 ]; then
  # depending on RPC or REST use different TOR address
  if [ "${port}" == "10009" ]; then
    host=$(sudo cat /mnt/hdd/tor/lndrpc10009/hostname)
    port="10009"
    echo "# using TOR --> host ${host} port ${port}"
  elif [ "${port}" == "8080" ]; then
    host=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
    port="8080"
    echo "# using TOR --> host ${host} port ${port}"
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


#### RUN LNDCONNECT

# generate data parts
macaroon=$(sudo base64 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon | tr -d '=' | tr '/+' '_-' | tr -d '\n')
cert=$(sudo grep -v 'CERTIFICATE' /mnt/hdd/lnd/tls.cert | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# generate URI parameters
macaroonParameter="?macaroon=${macaroon}"
certParameter="&cert=${cert}"

# mute cert parameter (optional)
if [ ${addcert} -eq 0 ]; then
  certParameter=""
fi

# build lndconnect
# see spec here: https://github.com/LN-Zap/lndconnect/blob/master/lnd_connect_uri.md
lndconnect="lndconnect://${host}:${port}${macaroonParameter}${certParameter}"

# display qr code image on LCD
/home/admin/config.scripts/blitz.display.sh qr "${lndconnect}"

# show pairing info dialog
msg=""
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  msg="Make sure you are on the same local network.\n(WLAN same as LAN - use WIFI not cell network on phone).\n\n"
fi
if [ ${#usingIP2TOR} -gt 0 ] && [ ${forceTOR} -eq 0 ]; then
  msg="Your IP2TOR bridge '${usingIP2TOR}' is used for this connection.\n\n"
fi
msg="You should now see the pairing QR code on the RaspiBlitz LCD.\n\n${msg}${connectInfo}\n\nIf you dont have an LCD choose <Console QRcode>"
whiptail --backtitle "Connecting Mobile Wallet" \
	 --title "Pairing by QR code" \
	 --yes-button "Continue" \
	 --no-button "Console QRcode" \
	 --yesno "${msg}" 18 65
if [ $? -eq 1 ]; then
  # backup - show QR code on screen (not LCD)
  echo "##############"
  echo "qrencode -o - -t ANSIUTF8 -m2 "${lndconnect}""
  echo "##############"
  qrencode -o - -t ANSIUTF8 -m2 "${lndconnect}"
  echo "Press ENTER when finished."
  read key
fi

# clean up
/home/admin/config.scripts/blitz.display.sh hide

echo "------------------------------"
echo "If the connection was not working:"
if [ ${#dynDomain} -gt 0 ]; then
  echo "- Make sure that your router is forwarding port ${port} to the Raspiblitz"
fi
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  echo "- Check that your WIFI devices can talk to the LAN devices on your router (deactivate IP isolation or guest mode)."
fi
echo "- try to refresh the TLS & macaroons: Main Menu 'EXPORT > 'RESET'"
echo "- check issues: https://github.com/rootzoll/raspiblitz/issues"
echo ""
