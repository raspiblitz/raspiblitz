#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#autoPilot} -eq 0 ]; then autoPilot="off"; fi
if [ ${#autoUnlock} -eq 0 ]; then autoUnlock="off"; fi
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
if [ ${#autoNatDiscovery} -eq 0 ]; then autoNatDiscovery="off"; fi
if [ ${#networkUPnP} -eq 0 ]; then networkUPnP="off"; fi
if [ ${#touchscreen} -eq 0 ]; then touchscreen=0; fi
if [ ${#lcdrotate} -eq 0 ]; then lcdrotate=0; fi
if [ ${#zerotier} -eq 0 ]; then zerotier="off"; fi
if [ ${#circuitbreaker} -eq 0 ]; then circuitbreaker="off"; fi

echo "# map LND to on/off"
lndNode="off"
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  lndNode="on"
fi

echo "# map CLN to on/off"
clnNode="off"
if [ "${lightning}" == "cln" ] || [ "${cln}" == "on" ]; then
  clnNode="on"
fi

echo "# map dropboxbackup to on/off"
DropboxBackup="off"
if [ ${#dropboxBackupTarget} -gt 0 ]; then DropboxBackup="on"; fi

echo "# map localbackup to on/off"
LocalBackup="off"
if [ ${#localBackupDeviceUUID} -gt 0 ] && [ "${localBackupDeviceUUID}" != "off" ]; then LocalBackup="on"; fi

echo "# map zerotier to on/off"
zerotierSwitch="off"
if [ "${zerotier}" != "off" ]; then zerotierSwitch="on"; fi

echo "# map parallel testnets to on/off"
parallelTestnets="off"
if [ "${testnet}" == "on"] || [ "${signet}" == "on" ]; then
  parallelTestnets="on"
fi

echo "# map domain to on/off"
domainValue="off"
dynDomainMenu='DynamicDNS'
if [ ${#dynDomain} -gt 0 ]; then
  domainValue="on"
  dynDomainMenu="${dynDomain}"
fi

echo "# map lcdrotate to on/off"
lcdrotateMenu='off'
if [ ${lcdrotate} -gt 0 ]; then
  lcdrotateMenu='on'
fi

echo "# map touchscreen to on/off"
touchscreenMenu='off'
if [ ${touchscreen} -gt 0 ]; then
  touchscreenMenu='on'
fi

echo "# map autopilot to on/off"
lndAutoPilotOn=$(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep -c 'autopilot.active=1')
if [ ${lndAutoPilotOn} -eq 1 ]; then
  autoPilot="on"
else
  autoPilot="off"
fi

echo "# map keysend to on/off"
keysend="on"
source <(sudo /home/admin/config.scripts/lnd.keysend.sh status)
if [ ${keysendOn} -eq 0 ]; then
  keysend="off"
fi

# show select dialog
echo "run dialog ..."

# BASIC MENU INFO
OPTIONS=()

# LCD options (only when running with LCD screen)
if [ "${displayClass}" == "lcd" ]; then
  OPTIONS+=(s 'Touchscreen' ${touchscreenMenu}) 
  OPTIONS+=(r 'LCD Rotate' ${lcdrotateMenu})  
fi

# Important basic options
OPTIONS+=(t 'Run behind Tor' ${runBehindTor})
OPTIONS+=(z 'ZeroTier' ${zerotierSwitch})

if [ ${#runBehindTor} -eq 0 ] || [ "${runBehindTor}" = "off" ]; then
  OPTIONS+=(y ${dynDomainMenu} ${domainValue})
  OPTIONS+=(b 'BTC UPnP (AutoNAT)' ${networkUPnP})  
fi
OPTIONS+=(p 'Parallel Testnet/Signet' ${parallelTestnets})

# LND & options (only when running LND)
OPTIONS+=(m 'LND LIGHTNING LABS NODE' ${lndNode}) 
if [ "${lndNode}" == "on" ]; then
  OPTIONS+=(a '-LND Channel Autopilot' ${autoPilot}) 
  OPTIONS+=(k '-LND Accept Keysend' ${keysend})  
  OPTIONS+=(c '-LND Circuitbreaker (firewall)' ${circuitbreaker})  
  OPTIONS+=(u '-LND Auto-Unlock' ${autoUnlock})  
  OPTIONS+=(d '-LND StaticChannelBackup DropBox' ${DropboxBackup})
  OPTIONS+=(e '-LND StaticChannelBackup USB Drive' ${LocalBackup})
  OPTIONS+=(l '-LND UPnP (AutoNAT)' ${autoNatDiscovery})
fi

# C-Lightning & options/PlugIns
OPTIONS+=(n 'CLN C-LIGHTNING NODE' ${clnNode}) 

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICES=$(dialog --title ' Node Settings & Options ' --checklist ' use spacebar to activate/de-activate ' $HEIGHT 45 $CHOICE_HEIGHT "${OPTIONS[@]}" 2>&1 >/dev/tty)
dialogcancel=$?
clear

# check if user canceled dialog
echo "dialogcancel(${dialogcancel}) (${CHOICE_HEIGHT})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 0
elif [ ${dialogcancel} -eq 255 ]; then
  echo "ESC pressed"
  exit 0
fi

needsReboot=0
anychange=0

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "a")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ]; then
  echo "Autopilot Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/lnd.autopilot.sh ${choice}
  needsReboot=1
else
  echo "Autopilot Setting unchanged."
fi

# Dynamic Domain
choice="off"; check=$(echo "${CHOICES}" | grep -c "y")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${domainValue}" != "${choice}" ]; then
  echo "Dynamic Domain changed .."
  anychange=1
  sudo /home/admin/config.scripts/internet.dyndomain.sh ${choice}
  needsReboot=1
else
  echo "Dynamic Domain unchanged."
fi

# UPnP
choice="off"; check=$(echo "${CHOICES}" | grep -c "b")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${networkUPnP}" != "${choice}" ]; then
  echo "BTC UPnP Setting changed .."
  anychange=1
  if [ "${choice}" = "on" ]; then
    echo "Starting BTC UPNP ..."
    /home/admin/config.scripts/network.upnp.sh on
    networkUPnP="on"
    needsReboot=1
  else
    echo "Stopping BTC UPNP ..."
    /home/admin/config.scripts/network.upnp.sh off
    networkUPnP="off"
    needsReboot=1
  fi
else
  echo "BTC UPnP Setting unchanged."
fi

# AutoNAT
choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoNatDiscovery}" != "${choice}" ]; then
  echo "AUTO NAT Setting changed .."
  anychange=1
  if [ "${choice}" = "on" ]; then
    echo "Starting autoNAT ..."
    /home/admin/config.scripts/lnd.autonat.sh on
    autoNatDiscovery="on"
    needsReboot=1
  else
    echo "Stopping autoNAT ..."
    /home/admin/config.scripts/lnd.autonat.sh off
    autoNatDiscovery="off"
    needsReboot=1
  fi
else
  echo "LND AUTONAT Setting unchanged."
fi

# Tor process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${runBehindTor}" != "${choice}" ]; then
  echo "Tor Setting changed .."

  # special actions if Tor is turned on
  if [ "${choice}" = "on" ]; then

    # inform user about privacy risk
    whiptail --title " PRIVACY NOTICE " --msgbox "
RaspiBlitz will now install/activate Tor & after reboot run behind it.

Please keep in mind that thru your LND node id & your previous IP history with your internet provider your lightning node could still be linked to your personal id even when running behind Tor. To unlink you from that IP history its recommended that after the switch/reboot to Tor you also use the REPAIR > RESET-LND option to create a fresh LND wallet. That might involve closing all channels & move your funds out of RaspiBlitz before that RESET-LND.
" 16 76

    # make sure AutoNAT & UPnP is off
    /home/admin/config.scripts/lnd.autonat.sh off
    /home/admin/config.scripts/network.upnp.sh off
  fi

  # change Tor
  anychange=1
  sudo /home/admin/config.scripts/internet.tor.sh ${choice}
  needsReboot=1

else
  echo "Tor Setting unchanged."
fi

# LND Auto-Unlock
choice="off"; check=$(echo "${CHOICES}" | grep -c "u")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoUnlock}" != "${choice}" ]; then
  echo "LND Autounlock Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/lnd.autounlock.sh ${choice}
  if [ $? -eq 0 ]; then
    l1="AUTO-UNLOCK IS NOW OFF"
    if [ "${choice}" = "on" ]; then
      l1="AUTO-UNLOCK IS NOW ACTIVE"
    fi  
    dialog --title 'OK' --msgbox "\n${l1}\n" 9 50
    needsReboot=1
  fi
else
  echo "LND Autounlock Setting unchanged."
fi

# lcd rotate
choice="0"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="1"; fi
if [ "${lcdrotate}" != "${choice}" ]; then
  echo "LCD Rotate Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.display.sh rotate ${choice}
  needsReboot=1
else
  echo "LCD Rotate Setting unchanged."
fi

# touchscreen
choice="0"; check=$(echo "${CHOICES}" | grep -c "s")
if [ ${check} -eq 1 ]; then choice="1"; fi
if [ "${touchscreen}" != "${choice}" ]; then
  echo "Touchscreen Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.touchscreen.sh ${choice}
  if [ "${choice}" == "1" ]; then
    dialog --title 'Touchscreen Activated' --msgbox 'Touchscreen was activated - will reboot.\n\nAfter reboot use the SCREEN option in main menu to calibrate the touchscreen.' 9 48
  fi
  needsReboot=1
else
  echo "Touchscreen Setting unchanged."
fi

# circuitbreaker
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${circuitbreaker}" != "${choice}" ]; then
  echo "Circuitbreaker Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/bonus.circuitbreaker.sh ${choice}
else
  echo "Circuitbreaker Setting unchanged."
fi

# DropBox process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "d")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${DropboxBackup}" != "${choice}" ]; then
  echo "DropBox Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/dropbox.upload.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    # doing initial upload so that user can see result
    source /mnt/hdd/raspiblitz.conf
    sudo /home/admin/config.scripts/dropbox.upload.sh upload ${dropboxBackupTarget} /mnt/hdd/lnd/data/chain/${network}/${chain}net/channel.backup
  fi
else
  echo "Dropbox backup setting unchanged."
fi

# LocalBackup process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "e")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${LocalBackup}" != "${choice}" ]; then
  echo "BackupdDevice Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.backupdevice.sh ${choice}
else
  echo "BackupdDevice setting unchanged."
fi

# Keysend process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "k")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${keysend}" != "${choice}" ]; then
  echo "keysend setting changed .."
  anychange=1
  needsReboot=1
  sudo -u admin /home/admin/config.scripts/lnd.keysend.sh ${choice}
  dialog --msgbox "Accept Keysend is now ${choice} after Reboot." 5 46
else
  echo "keysend setting unchanged."
fi

# ZeroTier process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "z")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${zerotierSwitch}" != "${choice}" ]; then
  echo "zerotier setting changed .."
  anychange=1
  error=""
  source <(sudo -u admin /home/admin/config.scripts/bonus.zerotier.sh ${choice})
  if [ "${choice}" == "on" ]; then
    if [ ${#error} -eq 0 ]; then
      dialog --msgbox "Your RaspiBlitz joined the ZeroTier network." 6 46
    else
      if [ "${error}" != "cancel" ]; then
        dialog --msgbox "ZeroTier Error:\n${error}" 8 46
      fi
    fi
  else
    dialog --msgbox "ZeroTier is now OFF." 5 46
  fi
  
else
  echo "ZeroTier setting unchanged."
fi

# LND choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "m")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndNode}" != "${choice}" ]; then
  anychange=1
  echo "# LND NODE Setting changed .."
  if [ "${choice}" = "on" ]; then
    echo "# turning ON"
    /home/admin/config.scripts/lnd.chain.sh on mainnet
    if [ "${testnet}" == "on" ]; then
      /home/admin/config.scripts/lnd.chain.sh on testnet
    fi
    if [ "${signetnet}" == "on" ]; then
      /home/admin/config.scripts/lnd.chain.sh on signet
    fi
  else
    echo "# turning OFF"
    /home/admin/config.scripts/lnd.chain.sh off mainnet
    /home/admin/config.scripts/lnd.chain.sh off testnet
    /home/admin/config.scripts/lnd.chain.sh off signet
  fi
else
  echo "LND NODE setting unchanged."
fi

# CLN choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "n")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndNode}" != "${choice}" ]; then
  anychange=1
  echo "# C-Lightning NODE Setting changed .."
  if [ "${choice}" = "on" ]; then
    echo "# turning ON"
    /home/admin/config.scripts/cln.install.sh on mainnet
    if [ "${testnet}" == "on" ]; then
      /home/admin/config.scripts/cln.install.sh on testnet
    fi
    if [ "${signetnet}" == "on" ]; then
      /home/admin/config.scripts/cln.install.sh on signet
    fi
  else
    echo "# turning OFF"
    /home/admin/config.scripts/cln.install.sh off mainnet
    /home/admin/config.scripts/cln.install.sh off testnet
    /home/admin/config.scripts/cln.install.sh off signet
  fi
else
  echo "C-Lightning NODE setting unchanged."
fi

# parallel testnet process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "p")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${testnet}" != "${choice}" ]; then
  echo "# Parallel Testnets Setting changed .."
  anychange=1
  if [ "${choice}" = "on" ]; then
    /home/admin/config.scripts/bitcoin.chains.sh on testnet
    /home/admin/config.scripts/bitcoin.chains.sh on signet
    if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
      /home/admin/config.scripts/lnd.chain.sh on testnet
      /home/admin/config.scripts/lnd.chain.sh on signet
    fi
    if [ "${lightning}" == "cln" ] || [ "${cln}" == "on" ]; then
      /home/admin/config.scripts/cln.install.sh on testnet
      /home/admin/config.scripts/cln.install.sh on signet
    fi 
  else
    # just turn al lightning testnets off (even if not on before)
    /home/admin/config.scripts/lnd.chain.sh off testnet
    /home/admin/config.scripts/lnd.chain.sh off signet
    /home/admin/config.scripts/cln.install.sh off testnet
    /home/admin/config.scripts/cln.install.sh off signet
    /home/admin/config.scripts/bitcoin.chains.sh off testnet
    /home/admin/config.scripts/bitcoin.chains.sh off signet
  fi
  # make sure to reboot - nodes that people activate testnets can take a reboot
  needsReboot=1
else
  echo "# Testnet Setting unchanged."
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
