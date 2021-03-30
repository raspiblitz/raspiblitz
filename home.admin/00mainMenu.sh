#!/bin/bash

echo "Starting the main menu ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# MAIN MENU AFTER SETUP
source ${infoFile}
source ${configFile}

# FUNCTIONS

confirmation()
{
  local text=$1
  local yesButtonText=$2
  local noButtonText=$3
  local defaultno=$4
  local height=$5
  local width=$6
  local answer=-100

  if [ $defaultno ]; then
     whiptail --title " Confirmation " --defaultno --yes-button "$yesButtonText" --no-button "$noButtonText" --yesno " $text

  " $height $width
  else
    whiptail --title " Confirmation " --yes-button "$yesButtonText" --no-button "$noButtonText" --yesno " $text

  " $height $width
  fi
  answer=$?
  return $answer
}

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=19
WIDTH=64
CHOICE_HEIGHT=12
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
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "BTCPay Server Info")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${lit}" == "on" ]; then
  OPTIONS+=(LIT "LIT (loop, pool, faraday)")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCRPCexplorer}" == "on" ]; then
  OPTIONS+=(EXPLORE "BTC RPC Explorer")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${LNBits}" == "on" ]; then
  OPTIONS+=(LNBITS "LNbits Server")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${lndmanage}" == "on" ]; then
  OPTIONS+=(LNDMANAGE "LND Manage Script")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${loop}" == "on" ]; then
  OPTIONS+=(LOOP "Loop In/Out Service")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(MEMPOOL "Mempool Space")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${specter}" == "on" ]; then
  OPTIONS+=(SPECTER "Cryptoadvance Specter")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${joinmarket}" == "on" ]; then
  OPTIONS+=(JMARKET "JoinMarket")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${faraday}" == "on" ]; then
  OPTIONS+=(FARADAY "Faraday Channel Management")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${bos}" == "on" ]; then
  OPTIONS+=(BOS "Balance of Satoshis")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${pyblock}" == "on" ]; then
  OPTIONS+=(PYBLOCK "PyBlock")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(THUB "ThunderHub")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${zerotier}" == "on" ]; then
  OPTIONS+=(ZEROTIER "ZeroTier")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${pool}" == "on" ]; then
  OPTIONS+=(POOL "Lightning Pool")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${sphinxrelay}" == "on" ]; then
  OPTIONS+=(SPHINX "Sphinx Chat Relay")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${chantools}" == "on" ]; then
  OPTIONS+=(CHANTOOLS "ChannelTools (Fund Rescue)")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${circuitbreaker}" == "on" ]; then
  OPTIONS+=(CIRCUIT "Circuitbreaker (LND firewall)")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

# Basic Options
OPTIONS+=(INFO "RaspiBlitz Status Screen")
OPTIONS+=(LIGHTNING "LND Wallet Options")
OPTIONS+=(SETTINGS "Node Settings & Options")
OPTIONS+=(SERVICES "Additional Apps & Services")
OPTIONS+=(SYSTEM "Monitoring and configuration")
OPTIONS+=(CONNECT "Connect Apps & Show Credentials")
OPTIONS+=(SUBSCRIBE "Manage Subscriptions")
OPTIONS+=(PASSWORD "Change Passwords")

if [ "${touchscreen}" == "1" ]; then
  OPTIONS+=(SCREEN "Touchscreen Calibration")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

# final Options
OPTIONS+=(REPAIR "Repair Options")
OPTIONS+=(UPDATE "Check/Prepare RaspiBlitz Update")
OPTIONS+=(REBOOT "Reboot RaspiBlitz")
OPTIONS+=(OFF "PowerOff RaspiBlitz")

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Exit" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in
        INFO)
            echo "Gathering Information (please wait) ..."
            walletLocked=$(lncli getinfo 2>&1 | grep -c "Wallet is encrypted")
            if [ ${walletLocked} -eq 0 ]; then
              while :
                do

                # show the same info as on LCD screen
                /home/admin/00infoBlitz.sh

                # wait 6 seconds for user exiting loop
                echo ""
                echo -en "Screen is updating in a loop .... press 'x' now to get back to menu."
                read -n 1 -t 6 keyPressed
                echo -en "\rGathering information to update info ... please wait.                \n"  

                # check if user wants to abort session
                if [ "${keyPressed}" = "x" ]; then
                  echo ""
                  echo "Returning to menu ....."
                  sleep 4
                  break
                fi
              done

            else
              /home/admin/00raspiblitz.sh
              exit 0
            fi
            ;;
        LIGHTNING)
            /home/admin/99lightningMenu.sh
            ;;
        CONNECT)
            /home/admin/99connectMenu.sh
            ;;
        SYSTEM)
            /home/admin/99systemMenu.sh
            ;;
        SCREEN)
            dialog --title 'Touchscreen Calibration' --msgbox 'Choose OK and then follow the instructions on touchscreen for calibration.\n\nBest is to use a stylus for accurate touchscreen interaction.' 9 48
            /home/admin/config.scripts/blitz.touchscreen.sh calibrate
            ;;
        RTL)
            /home/admin/config.scripts/bonus.rtl.sh menu
            ;;
        BTCPAY)
            /home/admin/config.scripts/bonus.btcpayserver.sh menu
            ;;
        EXPLORE)
            /home/admin/config.scripts/bonus.btc-rpc-explorer.sh menu
            ;;
        ELECTRS)
            /home/admin/config.scripts/bonus.electrs.sh menu
            ;;
        LIT)
            /home/admin/config.scripts/bonus.lit.sh menu
            ;;
        LNBITS)
            /home/admin/config.scripts/bonus.lnbits.sh menu
            ;;
        LNDMANAGE)
            /home/admin/config.scripts/bonus.lndmanage.sh menu
            ;;
        LOOP)
            /home/admin/config.scripts/bonus.loop.sh menu
            ;;
        MEMPOOL)
            /home/admin/config.scripts/bonus.mempool.sh menu
            ;;
        SPECTER)
            /home/admin/config.scripts/bonus.cryptoadvance-specter.sh menu
            ;;
        JMARKET)
            sudo /home/admin/config.scripts/bonus.joinmarket.sh menu
            ;;
        FARADAY)
            sudo /home/admin/config.scripts/bonus.faraday.sh menu
            ;;
        BOS)
            sudo /home/admin/config.scripts/bonus.bos.sh menu
            ;;
		    PYBLOCK)
            sudo /home/admin/config.scripts/bonus.pyblock.sh menu
            ;;
        THUB)
            sudo /home/admin/config.scripts/bonus.thunderhub.sh menu
            ;;
        ZEROTIER)
            sudo /home/admin/config.scripts/bonus.zerotier.sh menu
            ;;
        POOL)
            sudo /home/admin/config.scripts/bonus.pool.sh menu
            ;;
        SPHINX)
            sudo /home/admin/config.scripts/bonus.sphinxrelay.sh menu
            ;;
        CHANTOOLS)
            sudo /home/admin/config.scripts/bonus.chantools.sh menu
            ;;
        CIRCUIT)
            sudo /home/admin/config.scripts/bonus.circuitbreaker.sh menu
            ;;    
        SUBSCRIBE)
            /home/admin/config.scripts/blitz.subscriptions.py
            ;;
        SERVICES)
            /home/admin/00settingsMenuServices.sh
            ;;
        SETTINGS)
            /home/admin/00settingsMenuBasics.sh
            ;;
        REPAIR)
            /home/admin/98repairMenu.sh
            if [ $? -eq 99 ]; then
              exit 1
            fi
            ;;
        PASSWORD)
            sudo /home/admin/config.scripts/blitz.setpassword.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              echo "Press ENTER to Reboot .."
              read key
              sudo /home/admin/XXshutdown.sh reboot
              exit 0
            fi
            ;;
        UPDATE)
            /home/admin/99updateMenu.sh
            ;;
        REBOOT)
	    clear
	    confirmation "Are you sure?" "Reboot" "Cancel" true 7 40
	    confirmationReboot=$?
	    if [ $confirmationReboot -eq 0 ]; then
               clear
               echo ""
               sudo /home/admin/XXshutdown.sh reboot
               exit 0
	    fi
            ;;
        OFF)
	    clear
	    confirmation "Are you sure?" "PowerOff" "Cancel" true 7 40
	    confirmationShutdown=$?
	    if [ $confirmationShutdown -eq 0 ]; then
               clear
               echo ""
               sudo /home/admin/XXshutdown.sh
               exit 0
	    fi
            ;;
        DELETE)
            sudo /home/admin/XXcleanHDD.sh
            sudo /home/admin/XXshutdown.sh reboot
            exit 0
            ;;
        *)
            clear
            echo "***********************************"
            echo "* RaspiBlitz Commandline"
            echo "* Here be dragons .. have fun :)"
            echo "***********************************"
	          echo "Bitcoin command line options: bitcoin-cli help"
            echo "LND command line options: lncli -h"
            echo "Back to main menu use command: raspiblitz"
            echo
            exit 0
esac

# go into loop - start script from beginning to load config/sate fresh
/home/admin/00mainMenu.sh
