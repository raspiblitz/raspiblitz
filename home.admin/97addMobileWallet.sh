#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

justLocal=1
aks4IP2TOR=0

# if TOR is activated then outside reach is possible (no notice)
if [ "${runBehindTor}" = "on" ]; then
  echo "# runBehindTor ON"
  justLocal=0
  aks4IP2TOR=1
fi

# if dynDomain is set connect from outside is possible (no notice)
if [ ${#dynDomain} -gt 0 ]; then
  echo "# dynDomain ON"
  justLocal=0
  aks4IP2TOR=0
fi

# if sshtunnel to 10009/8080 then outside reach is possible (no notice)
isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
if [ ${isForwarded} -gt 0 ]; then
  echo "# forward 10009 ON"
  justLocal=0
  aks4IP2TOR=0
fi
isForwarded=$(echo ${sshtunnel} | grep -c "8080<")
if [ ${isForwarded} -gt 0 ]; then
  echo "# forward 8080 ON"
  justLocal=0
  aks4IP2TOR=0
fi

# echo "# justLocal(${justLocal})"
# echo "# aks4IP2TOR(${aks4IP2TOR})"
# read key

# check if dynamic domain is set
if [ ${justLocal} -eq 1 ]; then
  whiptail --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
also from outside your local network you need to 
activate 'Services' -> 'DynamicDNS' FIRST.
OR use SSH tunnel forwarding for port 10009
OR have TOR activated.

Do you JUST want to connect with your mobile
when your are on the same LOCAL NETWORK?
" 15 54
  response=$?
  case $response in
    1) exit ;;
  esac
fi

if [ "${chain}" == "test" ]; then
  whiptail --title " Testnet Notice " --msgbox "You are running your node in testnet.
Not all mobile Apps may support running in testnet.
For full support switch to mainnet.
" 9 55
fi

# fuction to call for wallets that support TOR
connect="ip"
choose_IP_or_TOR()
{
  whiptail --title " How to Connect? " \
	--yes-button "TOR" \
	--no-button "IP/Domain" \
	--yesno "The mobile wallet you selected supports TOR.\nDo you want to connect over TOR to your RaspiBlitz or fallback to Domain/IP?" 9 60
	if [ $? -eq 0 ]; then
	  echo "# yes-button -> TOR"
	  connect="tor" 
	else
	  echo "# no-button -> IP"
	  connect="ip"
	fi
}

# fuction to if already activated or user wants to activate IP2TOR
# needs parameter: #1 "LND-REST-API" or "LND-GRPC-API"
ip2tor=""
checkIP2TOR()
{

  # check if IP2TOR service is already available
  error=""
  ip2tor=""
  source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service $1)
  if [ ${#error} -eq 0 ]; then
    ip2tor="$1"
  fi

  #echo "# ip2tor(${ip2tor})"
  #echo "# aks4IP2TOR(${aks4IP2TOR})"
  #read key
  
  # if IP2TOR is not already available:
  # and the checks from avove showed there is SSH forwarding / dynDNS
  # then ask user if IP2TOR subscription is wanted
  if [ ${#ip2tor} -eq 0 ] && [ ${aks4IP2TOR} -eq 1 ]; then
    whiptail --title " Want to use a IP2TOR Bridge? " --yes-button "Go To Shop" --no-button "No Thanks" --yesno "It can be hard to connect to your RaspiBlitz when away from home.\n\nDo you like to subscribe to a IP2TOR bridge service (that will give you a public IP while hidden behind TOR) and make it more easy to connect your mobile wallet?" 12 60
  	if [ $? -eq 0 ]; then
  	  echo "# yes-button -> Send To Shop"
	  port="10009"
	  toraddress=$(sudo cat /mnt/hdd/tor/lndrpc10009/hostname)
	  if [ "$1" == "LND-REST-API" ]; then
	    port="8080"
		toraddress=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
	  fi

	  userHasActiveChannels=$(sudo -u bitcoin lncli listchannels | grep -c '"active": true')
	  if [ ${userHasActiveChannels} -gt 0 ]; then
	    sudo -u admin /home/admin/config.scripts/blitz.subscriptions.ip2tor.py create-ssh-dialog "$1" "$toraddress" "$port"
	  else
	  	whiptail --title " Lightning not Ready " --msgbox "\nYou need at least one active Lightning channel.\n\nPlease make sure that your node is funded and\nyou have a confirmed and active channel running.\nThen try again to connect the mobile wallet." 13 52
	  	exit 0
	  fi
      clear
	fi
  fi

  # check again if IP2TOR service is now already available
  error=""
  source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-by-service "$1")
  if [ ${#error} -eq 0 ]; then
    ip2tor="$1"
  fi
}

# Options
OPTIONS=(ZAP_IOS "Zap Wallet (iOS)" \
        ZAP_ANDROID "Zap Wallet (Android)" \
        ZEUS_IOS "Zeus Wallet (iOS)" \
        ZEUS_ANDROID "Zeus Wallet (Android)" \
		SPHINX "Sphinx Chat (Android or iOS)"
	)

# add SEND MANY APP
OPTIONS+=(SENDMANY_ANDROID "SendMany (Android)") 

# Additinal Options with TOR
if [ "${runBehindTor}" = "on" ]; then
  OPTIONS+=(FULLY_NODED "Fully Noded (IOS+TOR)") 
fi

CHOICE=$(whiptail --clear --title "Choose Mobile Wallet" --menu "" 14 50 8 "${OPTIONS[@]}" 2>&1 >/dev/tty)

/home/admin/config.scripts/blitz.lcd.sh hide

clear
echo "creating install info ..."
case $CHOICE in
  CLOSE)
  	exit 1;
    ;;
	SPHINX)
	  if [ "${sphinxrelay}" != "on" ]; then
	  	whiptail --title " Install Sphinx Relay Server? " \
	    --yes-button "Install" \
		--no-button "Cancel" \
		--yesno "To use the Sphinx Chat App you need to install the Sphinx Relay Server on your RaspiBlitz. If you want to deinstall the relay later on, just switch it off under MENU > SERVICES.\n\nDo you want to install the Sphinx Relay Server now?" 14 60
	  	if [ "$?" = "0" ]; then
	      /home/admin/config.scripts/bonus.sphinxrelay.sh on
	  	else
		  echo "No install ... returning to main menu."
		  sleep 2
	  	  exit 0
		fi
	  fi
	  # make pairing thru sphinx relay script
      /home/admin/config.scripts/bonus.sphinxrelay.sh menu
	  exit 1;
	  ;;
	SHANGO_IOS)
	  appstoreLink="https://testflight.apple.com/join/WwCjFnS8"
	  /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Testflight and Shango on your iOS device" \
	    --yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-GRPC-API
      /home/admin/config.scripts/bonus.lndconnect.sh shango-ios ${connect}
	  exit 1;
	  ;;
	SHANGO_ANDROID)
	  appstoreLink="https://play.google.com/store/apps/details?id=com.shango"
	  /home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  whiptail --title "Install Shango on your Android Phone" \
		--yes-button "continue" \
		--no-button "link as QR code" \
		--yesno "At the moment this app is in public beta testing:\n\n${appstoreLink}\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue" 10 60
	  if [ $? -eq 1 ]; then
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-GRPC-API
	  /home/admin/config.scripts/bonus.lndconnect.sh shango-android ${connect}
      exit 1;
      ;;
  ZAP_IOS)
      appstoreLink="https://apps.apple.com/us/app/zap-bitcoin-lightning-wallet/id1406311960"
      #/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	  #whiptail --title "Install Testflight and Zap on your iOS device" \
	#	--yes-button "continue" \
	#	--no-button "link as QR code" \
	#	--yesno "Search for 'Zap Bitcoin' in Apple Appstore for basic version\nOr join public beta test for latest features:\n${appstoreLink}\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 11 65
	 # if [ $? -eq 1 ]; then
	  #  /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  #fi

      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/app_zap.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'Zap Bitcoin'\n\nCheck that logo is like on LCD & author: Zap Technologies LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-GRPC-API
	  see https://github.com/rootzoll/raspiblitz/issues/1001#issuecomment-634580257
      if [ ${#ip2tor} -eq 0 ]; then
	    choose_IP_or_TOR
	  fi
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-ios ${connect}
      exit 1;
    ;;
  ZAP_ANDROID)
      appstoreLink="https://play.google.com/store/apps/details?id=zapsolutions.zap"
      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/app_zap.png
	  whiptail --title "Install Zap on your Android Phone" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Android Play Store on your mobile phone.\n\nSearch for --> 'zap bitcoin app'\n\nCheck that logo is like on LCD and author is: Zap\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-GRPC-API
      if [ ${#ip2tor} -eq 0 ]; then
	    choose_IP_or_TOR
	  fi
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-android ${connect}
      exit 1;
    ;;
  SENDMANY_ANDROID)

      # check if keysend is activated first
	  source <(/home/admin/config.scripts/lnd.keysend.sh status)
	  if [ "${keysendOn}" == "0" ]; then
	    whiptail --title " KEYSEND NEEDED " --msgbox "
To use the chat feature of the SendMany app, you need to activate the Keysend feature first.

Please go to MAINMENU > SERVICES and activate KEYSEND first.
" 12 65
	    exit 1
	  fi

      appstoreLink="https://github.com/fusion44/sendmany/releases"
	  whiptail --title "Install SendMany APK from GithubReleases" \
	    --yes-button "Continue" \
		--no-button "Link as QR code" \
		--yesno "Download & install the SendMany APK (armeabi-v7) from GitHub:\n\n${appstoreLink}\n\nEasiest way to scan QR code on LCD and download/install.\n\nWhen installed and started -> continue." 13 65
	  if [ $? -eq 1 ]; then
	  	/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
	    /home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-GRPC-API
  	  /home/admin/config.scripts/bonus.lndconnect.sh sendmany-android ${connect}
      exit 1;
    ;;
  ZEUS_IOS)
      appstoreLink="https://testflight.apple.com/join/gpVFzEHN"
      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/app_zeus.png
	  whiptail --title "Install Testflight and Zeus on your iOS device" \
		--yes-button "Continue" \
		--no-button "Link as QR Code" \
		--yesno "At the moment this app is in public beta testing.\nFirst open Apple Apstore, search & install 'TestFlight' app.\n\nThen open the following link on your mobile:\n${appstoreLink}\n\nUse 'Open In TestFlight' option of your mobile browser.\nWhen Zeus is installed and started --> Continue." 14 65
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
		/home/admin/config.scripts/blitz.lcd.sh qr-console ${appstoreLink}
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-REST-API
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-ios ${connect}
  	  exit 1;
  	;;
  ZEUS_ANDROID)
      appstoreLink="https://play.google.com/store/apps/details?id=app.zeusln.zeus"
      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/app_zeus.png
	  whiptail --title "Install Zeus on your Android Phone" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Android Play Store on your mobile phone.\n\nSearch for --> 'zeus bitcoin app'\n\nCheck that logo is like on LCD and author is: Evan Kaloudis\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
	  checkIP2TOR LND-REST-API
      if [ ${#ip2tor} -eq 0 ]; then
	    choose_IP_or_TOR
	  fi
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-android ${connect}
  	  exit 1;
  	;;
  FULLY_NODED)
      appstoreLink="https://apps.apple.com/us/app/fully-noded/id1436425586"
      /home/admin/config.scripts/blitz.lcd.sh image /home/admin/raspiblitz/pictures/app_fullynoded.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'fully noded'\n\nCheck that logo is like on LCD and author is: Denton LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		/home/admin/config.scripts/blitz.lcd.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  /home/admin/config.scripts/blitz.lcd.sh hide
  	  /home/admin/config.scripts/bonus.fullynoded.sh
  	  exit 1;
  	;;
esac
