#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

CHAIN=mainnet

# for testnet
echo "services default values"
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#lnd} -eq 0 ]; then lnd="off"; fi
if [ ${#cln} -eq 0 ]; then cln="off"; fi
if [ ${#crtlWebinterface} -eq 0 ]; then crtlWebinterface="off"; fi
if [ ${#sparko} -eq 0 ]; then sparko="off"; fi

# show select dialog
echo "run dialog ..."

OPTIONS=()
OPTIONS+=(l "LND on $CHAIN" ${lnd})
OPTIONS+=(r "RTL for LND $CHAIN" ${rtlWebinterface})
OPTIONS+=(c "C-lightning on $CHAIN" ${cln})
OPTIONS+=(t "RTL for CLN on $CHAIN" ${crtlWebinterface})
OPTIONS+=(s "Sparko for CLN on $CHAIN" ${sparko})

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
  exit 1
elif [ ${dialogcancel} -eq 255 ]; then
  echo "ESC pressed"
  exit 1
fi

needsReboot=0
anychange=0

# lnd process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lnd}" != "${choice}" ]; then
  echo "# LND on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/lnd.chain.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      echo "# Successfully installed LND on $CHAIN"
    else
      l1="# !!! FAIL on LND on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/lnd.chain.sh on $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# LND on $CHAIN Setting unchanged."
fi

# cln process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${cln}" != "${choice}" ]; then
  echo "# CLN on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/cln.install.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      echo "# Successfully installed CLN on $CHAIN"
    else
      l1="# !!! FAIL on CLN on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cln.install.sh on $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# CLN on $CHAIN Setting unchanged."
fi

# RTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${rtlWebinterface}" != "${choice}" ]; then
  echo "# RTL for LND $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} lnd $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start RTL
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

# cRTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${crtlWebinterface}" != "${choice}" ]; then
  echo "RTL for CLN $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} cln $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start cRTL
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu cln $CHAIN
    else
      l1="!!! FAIL on RTL for CLN $CHAIN install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on cln $CHAIN"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "RTL for CLN $CHAIN Setting unchanged."
fi

# sparko process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "s")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${sparko}" != "${choice}" ]; then
  echo "# Sparko on $CHAIN Setting changed .."
  anychange=1
  /home/admin/config.scripts/cln-plugin.sparko.sh ${choice} $CHAIN
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      /home/admin/config.scripts/cln-plugin.sparko.sh menu $CHAIN
    else
      l1="# !!! FAIL on Sparko on $CHAIN install !!!"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cln-plugin.sparko.sh on $CHAIN"
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