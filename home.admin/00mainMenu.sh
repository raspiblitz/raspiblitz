#!/bin/bash
echo "Starting the main menu ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# MAIN MENU AFTER SETUP
source ${infoFile}
source ${configFile}

# get the local network IP to be displayed on the lCD
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# BASIC MENU INFO
HEIGHT=13
WIDTH=64
CHOICE_HEIGHT=6
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()
plus=""
if [ "${runBehindTor}" = "on" ]; then
  plus=" / TOR"
fi
if [ ${#dynDomain} -gt 0 ]; then
  plus="${plus} / ${dynDomain}"
fi
BACKTITLE="${localip} / ${hostname} / ${network} / ${chain}${plus}"

if [ "${rtlWebinterface}" == "on" ]; then
  TITLE="Webinterface: http://${localip}:3000"
fi

# Put Activated Apps on top
if [ "${rtlWebinterface}" == "on" ]; then
  OPTIONS+=(RTL "RTL Web Node Manager")  
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "BTCPay Server Info")  
fi
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")  
fi
if [ "${lndmanage}" == "on" ]; then
  OPTIONS+=(LNDMANAGE "LND Manage Script")  
fi
if [ "${lndmanage}" == "on" ]; then
  OPTIONS+=(LOOP "Loop In/Out Service")  
fi

# Basic Options
OPTIONS+=(INFO "RaspiBlitz Status Screen")
OPTIONS+=(FUNDING "Fund your LND Wallet")
OPTIONS+=(CONNECT "Connect to a Peer")
OPTIONS+=(CHANNEL "Open a Channel with Peer")
if [ "${chain}" = "main" ]; then
  OPTIONS+=(lnbalance "Detailed Wallet Balances")
  OPTIONS+=(lnchannels "Lightning Channel List")
  OPTIONS+=(lnfwdreport "Lightning Forwarding Events Report")  
fi
OPTIONS+=(SEND "Pay an Invoice/PaymentRequest")
OPTIONS+=(RECEIVE "Create Invoice/PaymentRequest")
OPTIONS+=(SERVICES "Activate/Deactivate Services")
OPTIONS+=(MOBILE "Connect Mobile Wallet")
OPTIONS+=(EXPORT "Macaroons and TLS.cert")
OPTIONS+=(NAME "Change Name/Alias of Node")
OPTIONS+=(PASSWORD "Change Passwords")
OPTIONS+=(CASHOUT "Remove Funds from LND")

# Depending Options
openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | jq '.[] | length')
if [ ${#openChannels} -gt 0 ] && [ ${openChannels} -gt 0 ]; then
  OPTIONS+=(CLOSEALL "Close all open Channels")  
fi

if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(TOR "Monitor TOR Service")  
fi

if [ "${touchscreen}" == "1" ]; then
  OPTIONS+=(SCREEN "Touchscreen Calibration")  
fi

# final Options
OPTIONS+=(REPAIR "Repair Options")
OPTIONS+=(UPDATE "Check/Prepare RaspiBlitz Update")
OPTIONS+=(OFF "PowerOff RaspiBlitz")
OPTIONS+=(X "Console / Terminal")

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
        X)
            clear
            echo "***********************************"
            echo "* RaspiBlitz Commandline"
            echo "* Here be dragons .. have fun :)"
            echo "***********************************"
            echo "LND commandline options: lncli -h"
            echo "Back to main menu use command: raspiblitz"
            echo
            exit 1;
            ;;
        INFO)
            walletLocked=$(lncli getinfo 2>&1 | grep -c "Wallet is encrypted")
            if [ ${walletLocked} -eq 0 ]; then
              ./00infoBlitz.sh
              echo "Screen is not refreshing itself ... press ENTER to continue."
              read key
            fi
            ./00raspiblitz.sh
            ;;
        lnbalance)
            lnbalance ${network}
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        TOR)
            sudo -u bitcoin nyx
            ./00mainMenu.sh
            ;;
        SCREEN)
            dialog --title 'Touchscreen Calibration' --msgbox 'Choose OK and then follow the instructions on touchscreen for calibration.\n\nBest is to use a stylus for accurate touchscreen interaction.' 9 48
            /home/admin/config.scripts/blitz.touchscreen.sh calibrate
            ./00mainMenu.sh
            ;;
        RTL)
            /home/admin/config.scripts/bonus.rtl.sh menu
            ./00mainMenu.sh
            ;;
        BTCPAY)
            /home/admin/config.scripts/bonus.btcpayserver.sh menu
            ./00mainMenu.sh
            ;;
        ELECTRS)
            /home/admin/config.scripts/bonus.electrs.sh menu
            ./00mainMenu.sh
            ;;
        LNDMANAGE)
            /home/admin/config.scripts/bonus.lndmanage.sh menu
            ./00mainMenu.sh
            ;;
        LOOP)
            /home/admin/config.scripts/bonus.loop.sh menu
            ./00mainMenu.sh
            ;;
        lnchannels)
            lnchannels ${network}
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        lnfwdreport)
            ./XXlnfwdreport.sh 
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        CONNECT)
            ./BBconnectPeer.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        FUNDING)
            ./BBfundWallet.sh
            ./00mainMenu.sh
            ;;
        CASHOUT)
            ./BBcashoutWallet.sh
            ./00mainMenu.sh
            ;;
        CHANNEL)
            ./BBopenChannel.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        SEND)
            ./BBpayInvoice.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        RECEIVE)
            ./BBcreateInvoice.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        SERVICES)
            ./00settingsMenuServices.sh
            ./00mainMenu.sh
            ;;
        CLOSEALL)
            ./BBcloseAllChannels.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        MOBILE)
            ./97addMobileWallet.sh
            ./00mainMenu.sh
            ;;
        EXPORT)
            sudo /home/admin/config.scripts/lnd.export.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        NAME)
            sudo /home/admin/config.scripts/lnd.setname.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              sudo -u bitcoin ${network}-cli stop
              echo "Press ENTER to Reboot."
              read key
              sudo /home/admin/XXshutdown.sh reboot
            else
              ./00mainMenu.sh
            fi
            ;;
        REPAIR)
            ./98repairMenu.sh
            ./00mainMenu.sh
            ;;
        PASSWORD)
            sudo /home/admin/config.scripts/blitz.setpassword.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              echo "Press ENTER to Reboot .."
              read key
              sudo /home/admin/XXshutdown.sh reboot
            else
              echo "Press ENTER to return to main menu .."
              read key
              ./00mainMenu.sh
            fi
            ;;
        OFF)
            echo ""
            echo "LCD turns white when shutdown complete."
            echo "Then wait 5 seconds and disconnect power."
            echo "-----------------------------------------------"
            echo "stop lnd - please wait .."
            sudo systemctl stop lnd
            echo "stop ${network}d (1) - please wait .."
            sudo -u bitcoin ${network}-cli stop
            sleep 10
            echo "stop ${network}d (2) - please wait .."
            sudo systemctl stop ${network}d
            sleep 3
            sync
            echo "starting shutdown ..."
            sudo shutdown now
            exit 0
            ;;
        DELETE)
            sudo ./XXcleanHDD.sh
            sudo /home/admin/XXshutdown.sh reboot
            exit 0
            ;;   
        UPDATE)
            /home/admin/99checkUpdate.sh
            ./00mainMenu.sh
            exit 0
            ;;   
esac
