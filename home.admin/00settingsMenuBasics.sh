#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#autoPilot} -eq 0 ]; then autoPilot="off"; fi
if [ ${#autoUnlock} -eq 0 ]; then autoUnlock="off"; fi
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
if [ ${#networkUPnP} -eq 0 ]; then networkUPnP="off"; fi
if [ ${#touchscreen} -eq 0 ]; then touchscreen=0; fi
if [ ${#lcdrotate} -eq 0 ]; then lcdrotate=0; fi
if [ ${#zerotier} -eq 0 ]; then zerotier="off"; fi
if [ ${#circuitbreaker} -eq 0 ]; then circuitbreaker="off"; fi
if [ ${#clboss} -eq 0 ]; then clboss="off"; fi
if [ ${#clEncryptedHSM} -eq 0 ]; then clEncryptedHSM="off"; fi
if [ ${#clAutoUnlock} -eq 0 ]; then clAutoUnlock="off"; fi
if [ ${#blitzapi} -eq 0 ]; then blitzapi="off"; fi

echo "# map LND to on/off"
lndNode="off"
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  lndNode="on"
fi

echo "# map CL to on/off"
clNode="off"
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  clNode="on"
fi

echo "# map nextcloudbackup to on/off"
NextcloudBackup="off"
if [ $nextcloudBackupServer ] && [ $nextcloudBackupUser ] && [ $nextcloudBackupPassword ]; then NextcloudBackup="on"; fi

echo "# map localbackup to on/off"
LocalBackup="off"
if [ ${#localBackupDeviceUUID} -gt 0 ] && [ "${localBackupDeviceUUID}" != "off" ]; then LocalBackup="on"; fi

echo "# map zerotier to on/off"
zerotierSwitch="off"
if [ "${zerotier}" != "off" ]; then zerotierSwitch="on"; fi

echo "# map parallel testnets to on/off"
parallelTestnets="off"
if [ "${testnet}" == "on" ] || [ "${signet}" == "on" ]; then
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

echo "# map clboss to on/off"
clbossMenu='off'
if [ "${clboss}" == "on" ]; then
  clbossMenu='on'
fi

echo "# map clEncryptedHSM to on/off"
clEncryptedHSMMenu='off'
if [ "${clEncryptedHSM}" == "on" ]; then
  clEncryptedHSMMenu='on'
fi

echo "# map clAutoUnlock to on/off"
clAutoUnlockMenu='off'
if [ "${clAutoUnlock}" == "on" ]; then
  clAutoUnlockMenu='on'
fi

echo "# map keysend to on/off (may take time)"
keysend="on"
source <(sudo /home/admin/config.scripts/lnd.keysend.sh status)
if [ ${keysendOn} -eq 0 ]; then
  keysend="off"
fi

# show select dialog
echo "run dialog ..."

# BASIC MENU INFO
OPTIONS=()

OPTIONS+=(A 'Blitz API + WebUI' ${blitzapi})

# LCD options (only when running with LCD screen)
if [ "${displayClass}" == "lcd" ]; then
  OPTIONS+=(s 'Touchscreen (experimental)' ${touchscreenMenu})
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
  OPTIONS+=(x '-LND StaticChannelBackup on Nextcloud' ${NextcloudBackup})
  OPTIONS+=(e '-LND StaticChannelBackup USB Drive' ${LocalBackup})
fi

# C-Lightning & options/PlugIns
OPTIONS+=(n 'CL C-LIGHTNING NODE' ${clNode})
if [ "${clNode}" == "on" ]; then
  OPTIONS+=(o '-CL CLBOSS Automatic Node Manager' ${clbossMenu})
  OPTIONS+=(h '-CL Wallet Encryption' ${clEncryptedHSMMenu})
  if [ "${clEncryptedHSM}" == "on" ]; then
    OPTIONS+=(q '-CL Auto-Unlock' ${clAutoUnlockMenu})
  fi
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICES=$(dialog --title ' Node Settings & Options ' --checklist ' use spacebar to activate/de-activate ' $HEIGHT 55 $CHOICE_HEIGHT "${OPTIONS[@]}" 2>&1 >/dev/tty)
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

# Blitz API + webUI process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "A")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${blitzapi}" != "${choice}" ]; then
  echo "Blitz API + webUI settings changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.web.api.sh ${choice}
  sudo /home/admin/config.scripts/blitz.web.ui.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    whiptail --title " Installed Blitz API + webUI" --msgbox "\
The Blitz API + webUI was installed.\n
See the status screen for more info.\n
" 10 35
  fi
else
  echo "Blitz API + webUI Setting unchanged."
fi

# LND AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "a")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ] && [ "${lndNode}" == "on" ]; then
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

    /home/admin/config.scripts/network.upnp.sh off
  fi

  # change Tor
  anychange=1
  sudo /home/admin/config.scripts/tor.network.sh ${choice}
  needsReboot=1

else
  echo "Tor Setting unchanged."
fi

# LND Auto-Unlock
choice="off"; check=$(echo "${CHOICES}" | grep -c "u")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoUnlock}" != "${choice}" ] && [ "${lndNode}" == "on" ]; then
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

# LND circuitbreaker
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${circuitbreaker}" != "${choice}" ] && [ "${lndNode}" == "on" ]; then
  echo "Circuitbreaker Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/bonus.circuitbreaker.sh ${choice}
else
  echo "Circuitbreaker Setting unchanged."
fi

# Nextcloud process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "x")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${NextcloudBackup}" != "${choice}" ]; then
  echo "Nextcloud Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/nextcloud.upload.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    # doing initial upload so that user can see result
    source /mnt/hdd/raspiblitz.conf
    sudo /home/admin/config.scripts/nextcloud.upload.sh upload /mnt/hdd/lnd/data/chain/${network}/${chain}net/channel.backup
  fi
else
  echo "Nextcloud backup setting unchanged."
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

# LND Keysend process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "k")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${keysend}" != "${choice}" ] && [ "${lndNode}" == "on" ]; then
  echo "keysend setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/lnd.keysend.sh ${choice}
  sudo systemctl restart lnd
  dialog --msgbox "Accept Keysend on LND mainnet is now ${choice}.\n\nLND restarted - you might need to unlock wallet." 7 52
  sudo -u admin /home/admin/config.scripts/lnd.unlock.sh
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
    /home/admin/config.scripts/lnd.install.sh on mainnet initwallet
    sudo /home/admin/config.scripts/lnd.install.sh display-seed mainnet delete
    if [ "${testnet}" == "on" ]; then
      /home/admin/config.scripts/lnd.install.sh on testnet initwallet
    fi
    if [ "${signet}" == "on" ]; then
      /home/admin/config.scripts/lnd.install.sh on signet initwallet
    fi
  else
    echo "# turning OFF"
    /home/admin/config.scripts/lnd.install.sh off mainnet
    /home/admin/config.scripts/lnd.install.sh off testnet
    /home/admin/config.scripts/lnd.install.sh off signet
  fi
else
  echo "LND NODE setting unchanged."
fi

# CL choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "n")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${clNode}" != "${choice}" ]; then
  anychange=1
  echo "# C-Lightning NODE Setting changed .."
  if [ "${choice}" = "on" ]; then
    echo "# turning ON"

    /home/admin/config.scripts/cl.install.sh on mainnet
    # generate wallet from seedwords or just display (write to dev/null to not write seed words to logs)
    /home/admin/config.scripts/cl.hsmtool.sh new mainnet 1>/dev/null
    if [ "${testnet}" == "on" ]; then
      # no seed for testnet
      /home/admin/config.scripts/cl.install.sh on testnet
    fi
    if [ "${signet}" == "on" ]; then
      # no seed for signet
      /home/admin/config.scripts/cl.install.sh on signet
    fi

    # make sure that cln-grpc is on for the WebAPI
    /home/admin/config.scripts/cl-plugin.cln-grpc.sh install
    /home/admin/config.scripts/cl-plugin.cln-grpc.sh on

  else
    echo "# turning OFF"
    /home/admin/config.scripts/cl-plugin.cln-grpc.sh off
    /home/admin/config.scripts/cl.install.sh off mainnet
    /home/admin/config.scripts/cl.install.sh off testnet
    /home/admin/config.scripts/cl.install.sh off signet
  fi
else
  echo "C-Lightning NODE setting unchanged."
fi

# CLBOSS process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "o")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${clboss}" != "${choice}" ] && [ "${clNode}" == "on" ]; then
  echo "CLBOSS Setting changed .."
  anychange=1
  if [ ${choice} = on ]; then
    if /home/admin/config.scripts/cl-plugin.clboss.sh info; then
      sudo /home/admin/config.scripts/cl-plugin.clboss.sh on
    else
      echo "CLBOSS install was cancelled."
      sleep 2
    fi
  else
    sudo /home/admin/config.scripts/cl-plugin.clboss.sh off
  fi
  needsReboot=0
else
  echo "CLBOSS Setting unchanged."
fi

# clEncryptedHSM process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "h")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${clEncryptedHSM}" != "${choice}" ] && [ "${clNode}" == "on" ]; then
  echo "clEncryptedHSM Setting changed .."
  anychange=1
  if [ "${choice}" == "on" ]; then
    sudo /home/admin/config.scripts/cl.hsmtool.sh encrypt mainnet
  else
    /home/admin/config.scripts/cl.hsmtool.sh decrypt mainnet
  fi
  needsReboot=0
else
  echo "clEncryptedHSM Setting unchanged."
fi

# clAutoUnlock process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "q")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${clAutoUnlock}" != "${choice}" ] && [ "${clNode}" == "on" ]; then
  echo "clAutoUnlock Setting changed .."
  anychange=1
  if [ "${choice}" == "on" ]; then
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-on mainnet
  else
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-off mainnet
  fi
  needsReboot=0
else
  echo "clAutoUnlock Setting unchanged."
fi

# parallel testnet process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "p")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${testnet}" != "${choice}" ] || \
   [ "${signet}" != "${choice}" ]; then
  echo "# Parallel Testnets Setting changed .."
  anychange=1
  if [ "${choice}" = "on" ]; then
    /home/admin/config.scripts/bitcoin.install.sh on testnet
    /home/admin/config.scripts/bitcoin.install.sh on signet
    if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
      /home/admin/config.scripts/lnd.install.sh on testnet initwallet
      /home/admin/config.scripts/lnd.install.sh on signet initwallet
    fi
    if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
      /home/admin/config.scripts/cl.install.sh on testnet
      /home/admin/config.scripts/cl.install.sh on signet
    fi
  else
    # just turn all lightning testnets off (even if not on before)
    /home/admin/config.scripts/lnd.install.sh off testnet
    /home/admin/config.scripts/lnd.install.sh off signet
    /home/admin/config.scripts/cl.install.sh off testnet
    /home/admin/config.scripts/cl.install.sh off signet
    /home/admin/config.scripts/bitcoin.install.sh off testnet
    /home/admin/config.scripts/bitcoin.install.sh off signet
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
