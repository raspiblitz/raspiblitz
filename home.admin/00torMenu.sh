#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# correct Hidden Services for RTL and BTC-RPC-Explorer
if [ $(sudo cat /etc/tor/torrc | grep "HiddenServicePort 3000" -c) -eq 1 ]; then
  torNeedsRestart=1
  sudo sed -i "s/^HiddenServicePort 3000 127.0.0.1:3000/HiddenServicePort 80 127.0.0.1:3000/g" /etc/tor/torrc
elif [ $(sudo cat /etc/tor/torrc | grep "HiddenServicePort 3002" -c) -eq 1 ]; then
  torNeedsRestart=1
  sudo sed -i "s/^HiddenServicePort 3002 127.0.0.1:3002/HiddenServicePort 80 127.0.0.1:3002/g" /etc/tor/torrc
else
  torNeedsRestart=0
fi

if [ $torNeedsRestart -eq 1 ]; then
  sudo systemctl restart tor
  echo "Restarting Tor after fixing Hidden Service ports"
  sleep 5
fi

# add value for ElectRS to raspi config if needed
if [ ${#ElectRS} -eq 0 ]; then
  echo "ElectRS=off" >> /mnt/hdd/raspiblitz.conf
fi
isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
if [ ${isInstalled} -eq 1 ]; then
 # setting value in raspiblitz config
  sudo sed -i "s/^ElectRS=.*/ElectRS=on/g" /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

echo "Run dialog ..."
echo "Installing the QR code generator (qrencode)"
./XXaptInstall.sh qrencode
./XXaptInstall.sh fbi

# BASIC MENU INFO
HEIGHT=14
WIDTH=64
CHOICE_HEIGHT=7
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()
plus=""

# Basic Options
OPTIONS+=(NYX "Monitor TOR" \
ZEUS "Connect Zeus over Tor (Android)" \
ZAP "Connect Zap over Tor (iOS TestFlight)" \
NODED "Connect Fully Noded (iOS TestFlight)" )
if [ "${rtlWebinterface}" = "on" ]; then
  OPTIONS+=(RTL "RTL web interface address")  
fi
if [ "${BTCRPCexplorer}" = "on" ]; then
  OPTIONS+=(EXPLORER "BTC-RPC-Explorer address")  
fi
if [ "${ElectRS}" = "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server address")  
fi
if [ "${BTCPayServer}" = "on" ]; then
  OPTIONS+=(BTCPAY "BTCPay Server address")  
fi

dialogcancel=$?
echo "done dialog"
clear

# check if user canceled dialog
echo "dialogcancel(${dialogcancel})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
fi

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

#clear
case $CHOICE in
        CLOSE)
            exit 1;
            ;;
        NYX)
            sudo -u bitcoin nyx
            ./00mainMenu.sh
            ;;
        ZEUS)
            ./97addMobileWalletTor.sh zeus
            ./00mainMenu.sh
            ;;
        ZAP)
            ./97addMobileWalletTor.sh zap
            ./00mainMenu.sh
            ;;
        NODED)
            ./97addMobileWalletFullyNoded.sh
            ./00mainMenu.sh
            ;;                 
        RTL)
            clear
            ./config.scripts/internet.hiddenservice.sh RTL 80 3000          
            ./XXdisplayHiddenServiceQR.sh RTL
            ./00mainMenu.sh
            ;;        
        EXPLORER)
            clear
            ./config.scripts/internet.hiddenservice.sh btc-rpc-explorer 80 3002        
            ./XXdisplayHiddenServiceQR.sh btc-rpc-explorer
            ./00mainMenu.sh
            ;;
        ELECTRS)
            clear
            ./config.scripts/internet.hiddenservice.sh electrs 50002 50002
            ./config.scripts/internet.hiddenservice.sh electrsTCP 50001 50001
            TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/electrs/hostname)
            echo ""
            echo "The Tor Hidden Service address for electrs is:"
            echo "$TOR_ADDRESS"
            echo ""
            echo "To connect the Electrumwallet through Tor open the Tor Browser and start Electrum with the options:" 
            echo "\`electrum --oneserver --server=$TOR_ADDRESS:50002:s --proxy socks5:127.0.0.1:9150\`"
            echo ""
            echo "See the docs for more detailed instructions to connect Electrum on Windows/Mac/Linux:"
            echo "https://github.com/openoms/bitcoin-tutorials/tree/master/electrs#connect-the-electrum-wallet-to-electrs"
            echo "" 
            echo "scan the QR to use the Tor address in Electrum on mobile:"
            qrencode -t ANSI256 $TOR_ADDRESS
            echo "Press ENTER to return to the menu"
            read key
            ./00mainMenu.sh
            ;;
        BTCPAY)
            clear
            ./config.scripts/internet.hiddenservice.sh btcpay 80 23000      
            ./XXdisplayHiddenServiceQR.sh btcpay
            ./00mainMenu.sh
            ;;               
esac            