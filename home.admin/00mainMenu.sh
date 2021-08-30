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

if [ ${chain} = test ];then
  netprefix="t"
elif [ ${chain} = sig ];then
  netprefix="s"
elif [ ${chain} = main ];then
  netprefix=""
fi

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()
plus=""
if [ "${runBehindTor}" = "on" ]; then
  plus=" / Tor"
fi
if [ ${#dynDomain} -gt 0 ]; then
  plus="/ ${dynDomain} ${plus}"
fi
if [ ${#lightning} -gt 0 ]; then
  plus="/ ${lightning} ${plus}"
fi
BACKTITLE="${localip} / ${hostname} / ${network} ${plus}"

# Put Activated Apps on top
if [ "${rtlWebinterface}" == "on" ] || [ "${crtlWebinterface}" == "on" ]; then
  OPTIONS+=(RTL "RTL Web Node Manager")
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "BTCPay Server Info")
fi
if [ "${lit}" == "on" ]; then
  OPTIONS+=(LIT "LIT (loop, pool, faraday)")
fi
if [ "${sparko}" == "on" ]; then
  OPTIONS+=(SPARKO "Sparko Webwallet")
fi
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")
fi
if [ "${BTCRPCexplorer}" == "on" ]; then
  OPTIONS+=(EXPLORE "BTC RPC Explorer")
fi
if [ "${LNBits}" == "on" ]; then
  OPTIONS+=(LNBITS "LNbits Server")
fi
if [ "${lndmanage}" == "on" ]; then
  OPTIONS+=(LNDMANAGE "LND Manage Script")
fi
if [ "${loop}" == "on" ]; then
  OPTIONS+=(LOOP "Loop In/Out Service")
fi
if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(MEMPOOL "Mempool Space")
fi
if [ "${specter}" == "on" ]; then
  OPTIONS+=(SPECTER "Specter Desktop")
fi
if [ "${joinmarket}" == "on" ]; then
  OPTIONS+=(JMARKET "JoinMarket")
fi
if [ "${faraday}" == "on" ]; then
  OPTIONS+=(FARADAY "Faraday Channel Management")
fi
if [ "${bos}" == "on" ]; then
  OPTIONS+=(BOS "Balance of Satoshis")
fi
if [ "${pyblock}" == "on" ]; then
  OPTIONS+=(PYBLOCK "PyBlock")
fi
if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(THUB "ThunderHub")
fi
if [ "${zerotier}" == "on" ]; then
  OPTIONS+=(ZEROTIER "ZeroTier")
fi
if [ "${pool}" == "on" ]; then
  OPTIONS+=(POOL "Lightning Pool")
fi
if [ "${sphinxrelay}" == "on" ]; then
  OPTIONS+=(SPHINX "Sphinx Chat Relay")
fi
if [ "${chantools}" == "on" ]; then
  OPTIONS+=(CHANTOOLS "ChannelTools (Fund Rescue)")
fi
if [ "${circuitbreaker}" == "on" ]; then
  OPTIONS+=(CIRCUIT "Circuitbreaker (LND firewall)")
fi
if [ "${testnet}" == "on" ]; then
  OPTIONS+=(TESTNET "Testnet Service Options")
fi
if [ ${chain} != "main" ]; then
  OPTIONS+=(MAINNET "Mainnet Service Options")
fi

# Basic Options
OPTIONS+=(INFO "RaspiBlitz Status Screen")

# if LND is active
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(LND "LND Wallet Options")
fi

# if C-Lightning is active
if [ "${lightning}" == "cln" ] || [ "${cln}" == "on" ]; then
  OPTIONS+=(CLN "C-lightning Wallet Options")
fi

OPTIONS+=(SETTINGS "Node Settings & Options")
OPTIONS+=(SERVICES "Additional Apps & Services")
OPTIONS+=(SYSTEM "Monitoring & Configuration")
OPTIONS+=(CONNECT "Connect Apps & Show Credentials")
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(SUBSCRIBE "Manage Subscriptions")
fi
OPTIONS+=(PASSWORD "Change Passwords")

if [ "${touchscreen}" == "1" ]; then
  OPTIONS+=(SCREEN "Touchscreen Calibration")
fi

# final Options
OPTIONS+=(REPAIR "Repair Options")
OPTIONS+=(UPDATE "Check/Prepare RaspiBlitz Update")
OPTIONS+=(REBOOT "Reboot RaspiBlitz")
OPTIONS+=(OFF "PowerOff RaspiBlitz")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
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
            while :
              do

              # show the same info as on LCD screen
              /home/admin/00infoBlitz.sh ${lightning} ${chain}net

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
            ;;
        LND)
            /home/admin/99lndMenu.sh
            ;;
        CLN)
            /home/admin/99clnMenu.sh ${chain}net
            ;;
        CONNECT)
            /home/admin/99connectMenu.sh
            ;;
        SYSTEM)
            /home/admin/99systemMenu.sh ${chain}net
            ;;
        SCREEN)
            dialog --title 'Touchscreen Calibration' --msgbox 'Choose OK and then follow the instructions on touchscreen for calibration.\n\nBest is to use a stylus for accurate touchscreen interaction.' 9 48
            /home/admin/config.scripts/blitz.touchscreen.sh calibrate
            ;;
        RTL)
            /home/admin/config.scripts/bonus.rtl.sh menu ${lightning}
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
        SPARKO)
            /home/admin/config.scripts/cln-plugin.sparko.sh menu mainnet
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
            /home/admin/config.scripts/bonus.specter.sh menu
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
        TESTNET)
            /home/admin/00parallelChainsMenu.sh testnet
            ;;    
        MAINNET)
            /home/admin/00parallelChainsMenu.sh mainnet
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
            ;;
        PASSWORD)
            sudo /home/admin/config.scripts/blitz.setpassword.sh
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
               sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
               exit 1
	          fi
            ;;
        OFF)
	          clear
	          confirmation "Are you sure?" "PowerOff" "Cancel" true 7 40
	          confirmationShutdown=$?
	          if [ $confirmationShutdown -eq 0 ]; then
               clear
               echo ""
               sudo /home/admin/config.scripts/blitz.shutdown.sh
               exit 1
	          fi
            ;;
        DELETE)
            sudo /home/admin/XXcleanHDD.sh
            sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
            exit 1
            ;;
        *)
            clear
            exit 1
esac

# forward exit code of submenu to outside loop
# 0 = continue loop / everything else = break loop and exit to terminal
exitCodeOfSubmenu=$?
if [ "${exitCodeOfSubmenu}" != "0" ]; then
  echo "# submenu signaled exit code '${exitCodeOfSubmenu}' --> forward to outside loop"
fi
exit ${exitCodeOfSubmenu}