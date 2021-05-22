#!/bin/bash

# Usage:
# 00chainMenu.sh <testnet|mainnets|ignet> <lnd|cln>

source /home/admin/raspiblitz.info
# add default value to raspi config if needed
if ! grep -Eq "^testnet=" /mnt/hdd/raspiblitz.conf; then
  echo "testnet=off" >> /mnt/hdd/raspiblitz.conf
fi
if ! grep -Eq "^LNdefault=" /mnt/hdd/raspiblitz.conf; then
  echo "LNdefault=lnd" >> /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

# CHAIN is signet | testnet | mainnet
if [ $# -gt 0 ] && [ $1 != ${chain}net ];then
  nonDefaultChain=1
  CHAIN=$1
else
  nonDefaultChain=0
  CHAIN=${chain}net
fi
# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  chainprefix="t"
  portprefix=1
elif [ ${CHAIN} = signet ];then
  chainprefix="s"
  portprefix=3
elif [ ${CHAIN} = mainnet ];then
  chainprefix=""
  portprefix=""
fi

# LNTYPE is lnd | cln
if [ $# -gt 1 ]&&[ $2 != $LNdefault ];then
  nonDefaultLNtype=1
  LNTYPE=$2
else
  nonDefaultLNtype=0
  LNTYPE=$LNdefault
fi

if [ ${LNTYPE} != lnd ]&&[ ${LNTYPE} != cln ];then
  echo "# ${LNTYPE} is not a supported LNTYPE"
  exit 1
fi

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=10
WIDTH=64
CHOICE_HEIGHT=3
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
if [ "${chainprefix}rtlWebinterface}" == "on" ]; then
  OPTIONS+=(RTL "RTL Web Node Manager for LND ${CHAIN}")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

if [ "${chainprefix}lnd" == "on" ]; then
  #TODO OPTIONS+=(LND "LND options for ${CHAIN}")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

if [ "${chainprefix}crtlWebinterface}" == "on" ]; then
  OPTIONS+=(cRTL "RTL Web Node Manager for C-lightning ${CHAIN}")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

if [ "${chainprefix}cln" == "on" ]; then
  #TODO OPTIONS+=(CLN "C-lightning options for ${CHAIN}")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

OPTIONS+=(INFO "RaspiBlitz Status Screen for ${CHAIN}")

if [ "$testnet" == "on" ]; then
OPTIONS+=(SERVICES "Additional Apps & Services on testnet")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
#TODO OPTIONS+=(SYSTEM "Monitoring & Configuration")
#TODO OPTIONS+=(CONNECT "Connect Apps & Show Credentials")

if [ $nonDefaultLNtype = 1 ];then
  OPTIONS+=(SWITCHLN "Make ${LNTYPE} the default lightning wallet")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

if [ $nonDefaultChain = 1 ];then
  OPTIONS+=(MKDEFAULT "Make ${CHAIN} the default chain")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi

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
   # #TODO
   # echo "Gathering Information (please wait) ..."
   # walletLocked=$(lncli getinfo 2>&1 | grep -c "Wallet is encrypted")
   # if [ ${walletLocked} -eq 0 ]; then
   #   while :
   #     do
   #     # show the same info as on LCD screen
   #     /home/admin/00infoBlitz.sh 
   #     # wait 6 seconds for user exiting loop
   #     echo ""
   #     echo -en "Screen is updating in a loop .... press 'x' now to get back to menu."
   #     read -n 1 -t 6 keyPressed
   #     echo -en "\rGathering information to update info ... please wait.                \n"  
   #     # check if user wants to abort session
   #     if [ "${keyPressed}" = "x" ]; then
   #       echo ""
   #       echo "Returning to menu ....."
   #       sleep 4
   #       break
   #     fi
   #   done
   # else
   #   /home/admin/00raspiblitz.sh
   #   exit 0
   # fi
   /home/admin/00infoBlitz.sh $CHAIN
  ;;
  RTL)
    /home/admin/config.scripts/bonus.rtl.sh menu lnd $CHAIN
    ;;
  cRTL)
    /home/admin/config.scripts/bonus.rtl.sh menu cln $CHAIN
    ;;
  LND)
    /home/admin/99lndMenu.sh $CHAIN
    # TODO
    ;;
  CLN)
    /home/admin/99CLNmenu.sh $CHAIN
    # TODO
    ;;
  SERVICES)
    /home/admin/00testnetServices.sh $CHAIN
    # TODO
    ;;
  SYSTEM)
    /home/admin/99systemMenu.sh $CHAIN
    # TODO
    ;;
  CONNECT)
    /home/admin/99connectMenu.sh $CHAIN
    # TODO
    ;;
  SWITCHLN)
    # setting value in raspi blitz config
    sudo sed -i "s/^LNdefault=.*/LNdefault=$LNTYPE/g" /mnt/hdd/raspiblitz.conf
    echo "# OK - Set LNdefault=$LNTYPE in /mnt/hdd/raspiblitz.conf"
    echo
    echo "Press ENTER to return to main menu."
    ;;
  MKDEFAULT)
    # setting value in raspi blitz config
    newchain=${CHAIN::-3}
    sudo sed -i "s/^chain=.*/chain=${newchain}/g" /mnt/hdd/raspiblitz.conf
    echo "# OK - Set chain=${newchain} in /mnt/hdd/raspiblitz.conf"
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
esac