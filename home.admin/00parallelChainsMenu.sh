#!/bin/bash

# Usage:
# 00parallelChainsMenu.sh <testnet|signet|mainnet> <lnd|cln>

source /home/admin/raspiblitz.info
# add default value to raspi config if needed
if ! grep -Eq "^testnet=" /mnt/hdd/raspiblitz.conf; then
  echo "testnet=off" >> /mnt/hdd/raspiblitz.conf
fi
if ! grep -Eq "^lightning=" /mnt/hdd/raspiblitz.conf; then
  echo "lightning=lnd" >> /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

# CHAIN is signet | testnet | mainnet
if [ $# -gt 0 ]; then
  CHAIN=$1
  if [ $1 != ${chain}net ];then
    nonDefaultChain=1
  fi
else
  nonDefaultChain=0
  CHAIN=${chain}net
fi

# LNTYPE is lnd | cln
if [ $# -gt 1 ]&&[ $2 != $lightning ];then
  nonDefaultLNtype=1
  LNTYPE=$2
else
  nonDefaultLNtype=0
  LNTYPE=$lightning
fi

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
WIDTH=64
BACKTITLE="${CHAIN} options"
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

# Put Activated Apps on top
if [ $chain = test ]&&[ "$trtlWebinterface" = "on" ]||\
   [ $chain = sig ]&& [ "$srtlWebinterface" = "on" ]||\
   [ $chain = main ]&&[ "$rtlWebinterface" = "on" ]; then
  OPTIONS+=(RTL "RTL Web Node Manager for LND ${CHAIN}")
fi

if [ $chain = test ]&&[ "$tlnd" = "on" ]||\
   [ $chain = sig ]&& [ "$slnd" = "on" ]||\
   [ $chain = main ]&&[ "$lnd" = "on" ]; then
  OPTIONS+=(LND "LND options for ${CHAIN}")
fi

if [ "$chain" = "test" ]&&[ "$tcrtlWebinterface" = "on" ]||\
   [ "$chain" = "sig" ]&& [ "$scrtlWebinterface" = "on" ]||\
   [ "$chain" = "main" ]&&[ "$crtlWebinterface" = "on" ]; then
  OPTIONS+=(cRTL "RTL Web Node Manager for C-lightning ${CHAIN}")
fi

if [ "$chain" = "test" ]&&[ "$tcln" = "on" ]||\
   [ "$chain" = "sig" ]&& [ "$scln" = "on" ]||\
   [ "$chain" = "main" ]&&[ "$cln" = "on" ]; then
  OPTIONS+=(CLN "C-lightning options for ${CHAIN}")
fi

OPTIONS+=(INFO "RaspiBlitz Status Screen for ${CHAIN}")

if [ "$testnet" == "on" ]; then
  OPTIONS+=(SERVICES "Additional Apps & Services on ${CHAIN}")
fi
OPTIONS+=(SYSTEM "Monitoring & Configuration")
#TODO OPTIONS+=(CONNECT "Connect Apps & Show Credentials")

if [ $nonDefaultLNtype = 1 ];then
  OPTIONS+=(SWITCHLN "Make ${LNTYPE} the default lightning wallet")
fi

if [ $nonDefaultChain = 1 ];then
  OPTIONS+=(MKDEFAULT "Make ${CHAIN} the default chain")
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Back" \
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
  RTL)
    /home/admin/config.scripts/bonus.rtl.sh menu lnd $CHAIN
    ;;
  cRTL)
    /home/admin/config.scripts/bonus.rtl.sh menu cln $CHAIN
    ;;
  LND)
    /home/admin/99lndMenu.sh $CHAIN
    ;;
  CLN)
    /home/admin/99clnMenu.sh $CHAIN
    ;;
  SERVICES)
    if [ $CHAIN = testnet ];then
      /home/admin/00parallelTestnetServices.sh
    elif [ $CHAIN = mainnet ];then
      /home/admin/00parallelMainnetServices.sh $CHAIN
    fi
    ;;
  SYSTEM)
    /home/admin/99systemMenu.sh $CHAIN
    ;;
  CONNECT)
    /home/admin/99connectMenu.sh $CHAIN
    ;;
  SWITCHLN)
    # setting value in raspi blitz config
    sudo sed -i "s/^lightning=.*/lightning=$LNTYPE/g" /mnt/hdd/raspiblitz.conf
    echo "# OK - Set lightning=$LNTYPE in /mnt/hdd/raspiblitz.conf"
    echo
    echo "Press ENTER to return to main menu."
    ;;
  MKDEFAULT)
    # setting value in raspi blitz config
    newchain=${CHAIN::-3}
    sudo sed -i "s/^chain=.*/chain=${newchain}/g" /mnt/hdd/raspiblitz.conf
    echo "# OK - Set chain=${newchain} in /mnt/hdd/raspiblitz.conf"
    sudo /home/admin/config.scripts/lnd.credentials.sh sync
    if grep -Eq "^specter=on" /mnt/hdd/raspiblitz.conf; then
      echo "# Restart Specter on $CHAIN"
      sudo systemctl restart specter.service
    fi
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
esac