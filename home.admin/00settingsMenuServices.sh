#!/bin/bash

# get raspiblitz config
source /mnt/hdd/raspiblitz.conf
if [ ${#autoPilot} -eq 0 ]; then autoPilot="off"; fi
if [ ${#autoNatDiscovery} -eq 0 ]; then autoNatDiscovery="off"; fi
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#chain} -eq 0 ]; then chain="main"; fi

# map chain to on/off
chainValue="off"
if [ "${chain}" = "test" ]; then chainValue="on"; fi

# show select dialog
CHOICES=$(dialog --checklist "Activate/Deactivate Services:" 15 40 6 \
1 "Channel Autopilot" ${autoPilot} \
2 "Testnet" ${chainValue} \
3 "Router AutoNAT" ${autoNatDiscovery} \
4 "Run behind TOR" ${runBehindTor} \
5 "RTL Webinterface" ${rtlWebinterface} \
2>&1 >/dev/tty)
dialogcancel=$?
clear

# check if user canceled dialog
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
fi

needsReboot=0

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "1")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ]; then
  echo "Autopilot Setting changed .."
  sudo /home/admin/config.scripts/lnd.autopilot.sh ${choice}
  needsReboot=1
else 
  echo "Autopilot Setting unchanged."
fi

# TESTNET process choice
choice="main"; check=$(echo "${CHOICES}" | grep -c "2")
if [ ${check} -eq 1 ]; then choice="test"; fi
if [ "${chain}" != "${choice}" ]; then
  if [ "${network}" = "litecoin" ] && [ "${choice}"="test" ]; then
     dialog --title 'FAIL' --msgbox 'Litecoin-Testnet not available.' 5 25
  else
    echo "Testnet Setting changed .."
    sudo /home/admin/config.scripts/network.chain.sh ${choice}net
    needsReboot=1
  fi
else 
  echo "Testnet Setting unchanged."
fi

# AUTONAT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "3")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoNatDiscovery}" != "${choice}" ]; then
  echo "AutoNAT Setting changed .."
  sudo /home/admin/config.scripts/lnd.autonat.sh ${choice}
  needsReboot=1
else 
  echo "AutoNAT Setting unchanged."
fi

# TOR process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "4")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${runBehindTor}" != "${choice}" ]; then
  echo "TOR Setting changed .."
  sudo /home/admin/config.scripts/internet.tor.sh ${choice}
  needsReboot=1
else 
  echo "TOR Setting unchanged."
fi

# RTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "5")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${rtlWebinterface}" != "${choice}" ]; then
  echo "RTL Webinterface Setting changed .."
  sudo /home/admin/config.scripts/bonus.rtl.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    l1="RTL web servcie should be installed - AFTER NEXT REBOOT:"
    l2="Try to open the following URL in your local webrowser"
    l3="and unlock your wallet from there with PASSWORD C."
    l4="---> http://${localip}:3000"
    dialog --title 'OK' --msgbox "${l1}\n${l2}\n${l3}\n${l4}" 9 25
  fi
  needsReboot=1
else
  echo "RTL Webinterface Setting unchanged."
fi

if [ ${needsReboot} -eq 1 ]; then
   sleep 2
   dialog --title 'OK' --msgbox 'System will reboot to activate changes.' 6 26
   echo "rebooting .."
   sudo shutdown -r now
fi