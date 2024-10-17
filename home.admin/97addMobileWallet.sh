#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

if [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo "Usage:" 
  echo "97addMobileWallet.sh <lnd|cl> <mainnet|testnet|signet>"
  echo "defaults from the configs are:"
  echo "ligthning=${lightning}"
  echo "chain=${chain}"
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars $1 $2)


justLocal=1

# if TOR is activated then outside reach is possible (no notice)
if [ "${runBehindTor}" = "on" ]; then
  echo "# runBehindTor ON"
  justLocal=0
fi

# if dynDomain is set connect from outside is possible (no notice)
if [ ${#dynDomain} -gt 0 ]; then
  echo "# dynDomain ON"
  justLocal=0
fi

# if sshtunnel to 10009/8080 then outside reach is possible (no notice)
isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
if [ ${isForwarded} -gt 0 ]; then
  echo "# forward 10009 ON"
  justLocal=0
fi

isForwarded=$(echo ${sshtunnel} | grep -c "8080<")
if [ ${isForwarded} -gt 0 ]; then
  echo "# forward 8080 ON"
  justLocal=0
fi

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

# function to call for wallets that support TOR
OPTIONS=()

if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
	OPTIONS+=(ZEUS_IOS "Zeus to LND (iOS)")
	OPTIONS+=(ZEUS_ANDROID "Zeus to LND (Android)")
	OPTIONS+=(ZAP_IOS "Zap to LND (iOS)")
	OPTIONS+=(ZAP_ANDROID "Zap/Bitbanana to LND (Android)")
	OPTIONS+=(SPHINX "Sphinx Chat to LND (Android/iOS)")
  	OPTIONS+=(SENDMANY_ANDROID "SendMany to LND (Android)")
	OPTIONS+=(FULLYNODED_LND "Fully Noded to LND REST (iOS+Tor)") 
fi

if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(ZEUS_CLNREST "Zeus to CLNrest (Android or iOS)")
	OPTIONS+=(ZEUS_CLREST "Zeus to C-Lightning-REST (Android or iOS)[DEPRECATED]")
	OPTIONS+=(FULLYNODED_CL "Fully Noded to CL REST (iOS+Tor)")
fi

# Additional Options with Tor
if [ "${runBehindTor}" = "on" ]; then
  OPTIONS+=(FULLYNODED_BTC "Fully Noded to bitcoinRPC (iOS+Tor)") 
fi

CHOICE=$(whiptail --clear --title "Choose Mobile Wallet" --menu "" 18 75 12 "${OPTIONS[@]}" 2>&1 >/dev/tty)

sudo /home/admin/config.scripts/blitz.display.sh hide

clear
echo "creating install info ..."
case $CHOICE in
  CLOSE)
  	exit 0;
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
	  exit 0;
	  ;;
  ZAP_IOS)
      appstoreLink="https://apps.apple.com/us/app/zap-bitcoin-lightning-wallet/id1406311960"
      sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_zap.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'Zap Bitcoin'\n\nCheck that logo is like on LCD & author: Zap Technologies LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		sudo /home/admin/config.scripts/blitz.display.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-ios tor
      exit 0;
    ;;
  ZAP_ANDROID)
	  whiptail --title "Install Zap/Bitbanana on your Android Phone" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Android Play Store on your mobile phone.\n\nSearch for --> 'bitbanana' (for updated fork)\nSearch for --> 'zap bitcoin app' (for original)\n\nWhen app is installed and started --> Continue." 12 65
  	  /home/admin/config.scripts/bonus.lndconnect.sh zap-android tor
      exit 0;
    ;;
  SENDMANY_ANDROID)

      # check if keysend is activated first
	  keysendOn=$(cat /mnt/hdd/lnd/lnd.conf | grep -c '^accept-keysend=1')
	  if [ "${keysendOn}" == "0" ]; then
	    whiptail --title " LND KEYSEND NEEDED " --msgbox "
To use the chat feature of the SendMany app, you need to activate the Keysend feature first.

Please go to MAINMENU > SYSTEM > LNDCONF and set accept-keysend=1 first.
" 12 65
	    exit 0
	  fi

      appstoreLink="https://github.com/fusion44/sendmany/releases"
	  whiptail --title "Install SendMany APK from GithubReleases" \
	    --yes-button "Continue" \
		--no-button "Link as QR code" \
		--yesno "Download & install the SendMany APK (armeabi-v7) from GitHub:\n\n${appstoreLink}\n\nEasiest way to scan QR code on LCD and download/install.\n\nWhen installed and started -> continue." 13 65
	  if [ $? -eq 1 ]; then
	  	sudo /home/admin/config.scripts/blitz.display.sh qr ${appstoreLink}
	    /home/admin/config.scripts/blitz.display.sh qr-console ${appstoreLink}
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh sendmany-android ip
      exit 0;
    ;;
  ZEUS_IOS)
	  whiptail --title "Install Zeus on your Android Phone" \
  --msgbox "Open the Android Play Store on your mobile phone.\n\nSearch for --> 'Zeus Wallet' by Atlas 21 Inc.\n\nWhen the app is installed and started --> OK" 11 65
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-ios tor
  	  exit 0;
  	;;
  ZEUS_ANDROID)
	  whiptail --title "Install Zeus on your Android Phone" \
  --msgbox "Open the Android Play Store on your mobile phone.\n\nSearch for --> 'Zeus Wallet' by Atlas 21 Inc.\n\nWhen the app is installed and started --> OK" 11 65
  	  /home/admin/config.scripts/bonus.lndconnect.sh zeus-android tor
  	  exit 0;
  	;;

  FULLYNODED_BTC)
      appstoreLink="https://apps.apple.com/us/app/fully-noded/id1436425586"
      sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_fullynoded.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'fully noded'\n\nCheck that logo is like on LCD and author is: Denton LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		sudo /home/admin/config.scripts/blitz.display.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/bonus.fullynoded.sh
  	  exit 0;
  	;;

  FULLYNODED_LND)
      appstoreLink="https://apps.apple.com/us/app/fully-noded/id1436425586"
      sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_fullynoded.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'fully noded'\n\nCheck that logo is like on LCD and author is: Denton LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		sudo /home/admin/config.scripts/blitz.display.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/bonus.lndconnect.sh fullynoded-lnd tor
  	  exit 0;
	;;

  FULLYNODED_CL)
	  if [ ! -L /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ];then
	    /home/admin/config.scripts/cl-plugin.http.sh on
	  fi
      appstoreLink="https://apps.apple.com/us/app/fully-noded/id1436425586"
      sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_fullynoded.png
	  whiptail --title "Install Fully Noded on your iOS device" \
		--yes-button "Continue" \
		--no-button "StoreLink" \
		--yesno "Open the Apple App Store on your mobile phone.\n\nSearch for --> 'fully noded'\n\nCheck that logo is like on LCD and author is: Denton LLC\nWhen app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		sudo /home/admin/config.scripts/blitz.display.sh qr ${appstoreLink}
		whiptail --title " App Store Link " --msgbox "\
To install app open the following link:\n
${appstoreLink}\n
Or scan the qr code on the LCD with your mobile phone.
" 11 70
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/cl-plugin.http.sh connect
  	  exit 0;
  	;;
ZEUS_CLNREST)
    sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_zeus.png
	  whiptail --title "Install Zeus on your Android or iOS Phone" \
			--yes-button "Continue" \
			--no-button "Cancel" \
			--yesno "Open the https://zeusln.app/ on your mobile phone to find the App Store link or binary for your phone.\n\nWhen the app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
			exit 0
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	/home/admin/config.scripts/cl-plugin.clnrest.sh connect
  	exit 0;
	;;
ZEUS_CLREST)
      sudo /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/app_zeus.png
	  whiptail --title "Install Zeus on your Android or iOS Phone" \
		--yes-button "Continue" \
		--no-button "Cancel" \
		--yesno "Open the https://zeusln.app/ on your mobile phone to find the App Store link or binary for your phone.\n\nWhen the app is installed and started --> Continue." 12 65
	  if [ $? -eq 1 ]; then
		exit 0
	  fi
	  sudo /home/admin/config.scripts/blitz.display.sh hide
  	  /home/admin/config.scripts/cl.rest.sh connect
  	  exit 0;
	;;
esac
