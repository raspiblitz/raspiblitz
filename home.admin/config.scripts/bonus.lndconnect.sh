#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to connect mobile apps with lnd connect"
 echo "# will autodetect dyndns, sshtunnel or TOR"
 echo "# bonus.lndconnect.sh [zap-ios|zap-android|zeus-ios|zeus-android|shango-ios|shango-android|sendmany-android] [?ip|tor]"
 exit 1
fi

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

#### MAKE SURE LNDCONNECT IS INSTALLED

# check if it is installed
# https://github.com/rootzoll/lndconnect
# using own fork of lndconnet because of this commit to fix for better QR code:
commit=82d7103bb8c8dd3c8ae8de89e3bc061eef82bb8f
isInstalled=$(lndconnect -h 2>/dev/null | grep "nocert" -c)
if [ $isInstalled -eq 0 ] || [ "$1" == "update" ]; then
  echo "# Installing lndconnect.."
  # make sure Go is installed
  /home/admin/config.scripts/bonus.go.sh on
  # get Go vars
  source /etc/profile
  # Install latest lndconnect from source:
  go get -d github.com/rootzoll/lndconnect
  cd $GOPATH/src/github.com/rootzoll/lndconnect
  git checkout $commit
  make
else
  echo "# lndconnect is already installed" 
fi

# recheck if install worked
isInstalled=$(lndconnect -h 2>/dev/null | grep "nocert" -c)
if [ $isInstalled -eq 0 ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL: Was not able to install/build lndconnect"
  echo "Retry later or report to developers with logs above."
  lndconnect -h
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!"
  read key
  exit 1
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
connector=""
host=""
port=""
extraparameter=""
supportsTOR=0
usingIP2TOR=""

if [ "${targetWallet}" = "zap-ios" ]; then
  connector="lndconnect"
  if [ ${forceTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses REST
    port="8080"
    extraparameter="--nocert"
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  
  
elif [ "${targetWallet}" = "zap-android" ]; then
  connector="lndconnect"
  if [ ${forceTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses gRPC
    port="10009"
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  

elif [ "${targetWallet}" = "zeus-ios" ]; then

  connector="lndconnect"
  port="8080"
  if [ ${#ip2torREST_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-REST-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torREST_IP}"
    port="${ip2torREST_PORT}"
  fi  
  if [ ${forceTOR} -eq 1 ]; then
    echo "error='no tor support'"
    exit 1
  fi

elif [ "${targetWallet}" = "zeus-android" ]; then

  connector="lndconnect"
  port="8080"
  if [ ${#ip2torREST_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-REST-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torREST_IP}"
    port="${ip2torREST_PORT}"
  fi  

elif [ "${targetWallet}" = "sendmany-android" ]; then

  connector="lndconnect"
  if [ ${forceTOR} -eq 1 ]; then
    # echo "error='no tor support'"
    # exit 1
    #port="8080"
    #extraparameter="--nocert"
    # deactivate TOR for now, because address is too long QR code is too big to be scanned by
    # app and so just make it possible to use local.
    forceTOR=0
  fi
  port="10009"
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  

elif [ "${targetWallet}" = "shango-ios" ]; then

  connector="shango"
  port="10009"
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi  
  if [ ${forceTOR} -eq 1 ]; then
    echo "error='no tor support'"
    exit 1
  fi

elif [ "${targetWallet}" = "shango-android" ]; then

  connector="shango"
  port="10009"
  if [ ${#ip2torGRPC_IP} -gt 0 ]; then
    # when IP2TOR bridge is available - force using that
    usingIP2TOR="LND-GRPC-API"
    forceTOR=0
    extraparameter=""
    host="${ip2torGRPC_IP}"
    port="${ip2torGRPC_PORT}"
  fi
  if [ ${forceTOR} -eq 1 ]; then
    echo "error='no tor support'"
    exit 1
  fi
 
else
  echo "error='unknown target wallet'"
  exit 1
fi

#### ADAPT PARAMETERS BASED RASPIBLITZ CONFIG

# get the local IP as default host
if [ ${#host} -eq 0 ]; then
    host=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
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

# special case: for Zeus android over TOR
hostscreen="${host}"
if [ "${targetWallet}" = "zeus-android" ] && [ ${forceTOR} -eq 1 ]; then
  # show TORv2 address on LCD (to make QR code smaller and scannable by Zeus)
  host=$(sudo cat /mnt/hdd/tor/lndrest8080fallback/hostname)
  # show TORv3 address on Screen
  hostscreen=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
fi

#### RUN LNDCONNECT

imagePath=""
datastring=""

if [ "${connector}" == "lndconnect" ]; then

  # get Go vars
  source /etc/profile

  # write qr code data to an image
  cd /home/admin
  lndconnect --host=${host} --port=${port} --image ${extraparameter}

  # display qr code image on LCD
  /home/admin/config.scripts/blitz.lcd.sh image /home/admin/lndconnect-qr.png

elif [ "${connector}" == "shango" ]; then

  # write qr code data to text file
  datastring=$(echo -e "${host}:${port},\n$(xxd -p -c2000 /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon),\n$(openssl x509 -sha256 -fingerprint -in /home/admin/.lnd/tls.cert -noout)")

  # display qr code on LCD
  /home/admin/config.scripts/blitz.lcd.sh qr "${datastring}"

else
  echo "error='unknown connector'"
  exit 1
fi

# show pairing info dialog
msg=""
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  msg="Make sure you are on the same local network.\n(WLAN same as LAN - use WIFI not cell network on phone).\n\n"
fi
if [ ${#usingIP2TOR} -gt 0 ]; then
  msg="Your IP2TOR bridge '${usingIP2TOR}' is used for this connection.\n\n"
fi
msg="You should now see the pairing QR code on the RaspiBlitz LCD.\n\n${msg}When you start the App choose to connect to your own node.\n(DIY / Remote-Node / lndconnect)\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <console QRcode> to see it in this window."
whiptail --backtitle "Connecting Mobile Wallet" \
	 --title "Pairing by QR code" \
	 --yes-button "continue" \
	 --no-button "console QRcode" \
	 --yesno "${msg}" 18 65
if [ $? -eq 1 ]; then
  # backup - show QR code on screen (not LCD)
  if [ "${connector}" == "lndconnect" ]; then
    lndconnect --host=${hostscreen} --port=${port} ${extraparameter}
    echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
    read key
  elif [ "${connector}" == "shango" ]; then
    /home/admin/config.scripts/blitz.lcd.sh qr-console ${datastring}
  fi
fi

# clean up
/home/admin/config.scripts/blitz.lcd.sh hide
shred -u ${imagePath} 2> /dev/null

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