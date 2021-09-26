#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

CHAIN=testnet

# for testnet
echo "services default values"
if [ ${#trtlWebinterface} -eq 0 ]; then trtlWebinterface="off"; fi
if [ ${#tlnd} -eq 0 ]; then tlnd="off"; fi
if [ ${#tcrtlWebinterface} -eq 0 ]; then tcrtlWebinterface="off"; fi
if [ ${#tcl} -eq 0 ]; then tcl="off"; fi
if [ ${#tsparko} -eq 0 ]; then tsparko="off"; fi

# show select dialog
echo "run dialog ..."

OPTIONS=()
OPTIONS+=(l "LND on $CHAIN" ${tlnd})
OPTIONS+=(r "RTL for LND $CHAIN" ${trtlWebinterface})
OPTIONS+=(c "C-lightning on $CHAIN" ${tcl})
OPTIONS+=(t "RTL for CL on $CHAIN" ${tcrtlWebinterface})
OPTIONS+=(s "Sparko for CL on $CHAIN" ${tsparko})

CHOICES=$(dialog --title ' Additional Services ' \
          --checklist ' use spacebar to activate/de-activate ' \
          12 45 5  "${OPTIONS[@]}" 2>&1 >/dev/tty)

dialogcancel=$?
echo "done dialog"
clear

# check if user canceled dialog
echo "dialogcancel(${dialogcancel})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 0
elif [ ${dialogcancel} -eq 255 ]; then
  echo "ESC pressed"
  exit 0
fi

needsReboot=0
anychange=0

# tlnd process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${tlnd}" != "${choice}" ]; then
  echo "# LND on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/lnd.install.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      echo "# Successfully installed LND on $CHAIN"
    else
      l1="# !!! FAIL on LND on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/lnd.install.sh on $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# LND on $CHAIN Setting unchanged."
fi

# tcl process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${tcl}" != "${choice}" ]; then
  echo "# CL on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/cl.install.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      echo "# Successfully installed CL on $CHAIN"
    else
      l1="# !!! FAIL on CL on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cl.install.sh on $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# CL on $CHAIN Setting unchanged."
fi

# tRTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${trtlWebinterface}" != "${choice}" ]; then
  echo "# RTL for LND $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} lnd $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start tRTL
      echo "# waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu lnd $CHAIN
    else
      l1="# !!! FAIL on RTL for LND $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on lnd $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# RTL for LND $CHAIN Setting unchanged."
fi

# ctRTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${tcrtlWebinterface}" != "${choice}" ]; then
  echo "RTL for CL $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} cl $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start tcRTL
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu cl $CHAIN
    else
      l1="!!! FAIL on RTL for CL $CHAIN install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on cl $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "RTL for CL $CHAIN Setting unchanged."
fi

# tsparko process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "s")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${tsparko}" != "${choice}" ]; then
  echo "# Sparko on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/cl-plugin.sparko.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      /home/admin/config.scripts/cl-plugin.sparko.sh menu $CHAIN
    else
      l1="# !!! FAIL on Sparko on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cl-plugin.sparko.sh on $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# Sparko on $CHAIN Setting unchanged."
fi



if [ ${anychange} -eq 0 ]; then
     dialog --msgbox "NOTHING CHANGED!\nUse Spacebar to check/uncheck services." 8 58
     exit 0
fi

if [ ${needsReboot} -eq 1 ]; then
   sleep 2
   dialog --pause "OK. System will reboot to activate changes." 8 58 8
   clear
   echo "rebooting .. (please wait)"
   # stop bitcoind
   sudo -u bitcoin ${network}-cli stop
   sleep 4
   sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
fi