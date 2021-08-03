#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#autoPilot} -eq 0 ]; then autoPilot="off"; fi
if [ ${#autoUnlock} -eq 0 ]; then autoUnlock="off"; fi
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
# if [ ${#chain} -eq 0 ]; then chain="main"; fi
if [ ${#autoNatDiscovery} -eq 0 ]; then autoNatDiscovery="off"; fi
if [ ${#networkUPnP} -eq 0 ]; then networkUPnP="off"; fi
if [ ${#touchscreen} -eq 0 ]; then touchscreen=0; fi
if [ ${#lcdrotate} -eq 0 ]; then lcdrotate=0; fi
if [ ${#zerotier} -eq 0 ]; then zerotier="off"; fi
if [ ${#circuitbreaker} -eq 0 ]; then circuitbreaker="off"; fi

echo "map dropboxbackup to on/off"
DropboxBackup="off"
if [ ${#dropboxBackupTarget} -gt 0 ]; then DropboxBackup="on"; fi

echo "map localbackup to on/off"
LocalBackup="off"
if [ ${#localBackupDeviceUUID} -gt 0 ] && [ "${localBackupDeviceUUID}" != "off" ]; then LocalBackup="on"; fi

echo "map zerotier to on/off"
zerotierSwitch="off"
if [ "${zerotier}" != "off" ]; then zerotierSwitch="on"; fi

# echo "map chain to on/off"
# chainValue="off"
# if [ "${chain}" = "test" ]; then chainValue="on"; fi

echo "map domain to on/off"
domainValue="off"
dynDomainMenu='DynamicDNS'
if [ ${#dynDomain} -gt 0 ]; then
  domainValue="on"
  dynDomainMenu="${dynDomain}"
fi

echo "map lcdrotate to on/off"
lcdrotateMenu='off'
if [ ${lcdrotate} -gt 0 ]; then
  lcdrotateMenu='on'
fi

echo "map touchscreen to on/off"
touchscreenMenu='off'
if [ ${touchscreen} -gt 0 ]; then
  touchscreenMenu='on'
fi

echo "check autopilot in lnd.conf"
lndAutoPilotOn=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'autopilot.active=1')
if [ ${lndAutoPilotOn} -eq 1 ]; then
  autoPilot="on"
else
  autoPilot="off"
fi

echo "map keysend to on/off"
keysend="on"
source <(sudo /home/admin/config.scripts/lnd.keysend.sh status)
if [ ${keysendOn} -eq 0 ]; then
  keysend="off"
fi

# show select dialog
echo "run dialog ..."


# BASIC MENU INFO
HEIGHT=19 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=45
OPTIONS=()

OPTIONS+=(t 'Run behind TOR' ${runBehindTor})
if [ "${displayClass}" == "lcd" ]; then
  OPTIONS+=(s 'Touchscreen' ${touchscreenMenu}) 
  OPTIONS+=(r 'LCD Rotate' ${lcdrotateMenu})  
fi
if [ ${chain} = "main" ];then
  OPTIONS+=(a 'Channel Autopilot' ${autoPilot}) 
  OPTIONS+=(k 'Accept Keysend' ${keysend})  
  # OPTIONS+=(n 'Testnet' ${chainValue}) # deprecated option
  # see the parallel network in SERVICES
  OPTIONS+=(c 'Circuitbreaker (LND firewall)' ${circuitbreaker})  
  OPTIONS+=(u 'LND Auto-Unlock' ${autoUnlock})  
  OPTIONS+=(d 'StaticChannelBackup on DropBox' ${DropboxBackup})
  OPTIONS+=(e 'StaticChannelBackup on USB Drive' ${LocalBackup})
fi
OPTIONS+=(z 'ZeroTier' ${zerotierSwitch})

if [ ${chain} = "main" ];then
  if [ ${#runBehindTor} -eq 0 ] || [ "${runBehindTor}" = "off" ]; then
    OPTIONS+=(y ${dynDomainMenu} ${domainValue})
    OPTIONS+=(b 'BTC UPnP (AutoNAT)' ${networkUPnP})  
    OPTIONS+=(l 'LND UPnP (AutoNAT)' ${autoNatDiscovery})
  fi
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}" / 3))
CHOICES=$(dialog \
          --title ' Node Settings & Options ' \
          --checklist ' use spacebar to activate/de-activate ' \
          $HEIGHT $WIDTH $CHOICE_HEIGHT \
          "${OPTIONS[@]}" 2>&1 >/dev/tty)

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

# deprecated - see https://github.com/rootzoll/raspiblitz/issues/2290
## TESTNET process choice - KEEP FIRST IN ORDER
#choice="main"; check=$(echo "${CHOICES}" | grep -c "n")
#if [ ${check} -eq 1 ]; then choice="test"; fi
#if [ "${chain}" != "${choice}" ]; then
#  if [ "${network}" = "litecoin" ] && [ "${choice}"="test" ]; then
#     dialog --title 'FAIL' --msgbox 'Litecoin-Testnet not available.' 5 25
#  elif [ "${BTCRPCexplorer}" = "on" ]; then
#     dialog --title 'NOTICE' --msgbox 'Please turn off BTC-RPC-Explorer FIRST\nbefore changing testnet.' 6 45
#     exit 1
#  elif [ "${BTCPayServer}" = "on" ]; then
#     dialog --title 'NOTICE' --msgbox 'Please turn off BTC-Pay-Server FIRST\nbefore changing testnet.' 6 45
#     exit 1
#  elif [ "${ElectRS}" = "on" ]; then
#     dialog --title 'NOTICE' --msgbox 'Please turn off Electrum-Rust-Server FIRST\nbefore changing testnet.' 6 48
#     exit 1
#  elif [ "${loop}" = "on" ]; then
#     dialog --title 'NOTICE' --msgbox 'Please turn off Loop-Service FIRST\nbefore changing testnet.' 6 48
#     exit 1
#  else
#    echo "Testnet Setting changed .."
#    anychange=1
#    sudo /home/admin/config.scripts/network.chain.sh ${choice}net
#    walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${choice}net/wallet.db 2>/dev/null | grep -c 'wallet.db')
#    if [ ${walletExists} -eq 0 ]; then
#      echo "Need to creating a new wallet ... wait 20secs"
#      sudo systemctl start lnd
#      sleep 20
#      tryAgain=1
#      while [ ${tryAgain} -eq 1 ]
#        do
#          echo "****************************************************************************"
#          echo "Creating a new LND Wallet for ${network}/${choice}net"
#          echo "****************************************************************************"
#          echo "A) For 'Wallet Password' use your PASSWORD C --> !! minimum 8 characters !!"
#          echo "B) Answer 'n' because you don't have a 'cipher seed mnemonic' (24 words) yet"
#          echo "C) For 'passphrase' to encrypt your 'cipher seed' use PASSWORD D (optional)"
#          echo "****************************************************************************"
#          source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${choice}net)
#          $lncli_alias create 2>error.out
#          error=$(sudo cat error.out)
#          if [ ${#error} -eq 0 ]; then
#            sleep 2
#            # WIN
#            tryAgain=0
#            echo "!!! Make sure to write down the 24 words (cipher seed mnemonic) !!!"
#            echo "If you are ready. Press ENTER."
#          else
#            # FAIL
#            tryAgain=1
#            echo "!!! FAIL ---> SOMETHING WENT WRONG !!!"
#            echo "${error}"
#            echo "Press ENTER to retry ... or CTRL-c to EXIT"
#          fi
#          read key
#        done
#      echo "Check for Macaroon .. (10sec)"
#      sleep 10
#      macaroonExists=$(sudo ls /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon | grep -c 'admin.macaroon')
#      if [ ${macaroonExists} -eq 0 ]; then
#        echo "*** PLEASE UNLOCK your wallet with PASSWORD C to create macaroon"
#        lncli unlock 2>/dev/null
#        sleep 6
#      fi
#      macaroonExists=$(sudo ls /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon | grep -c 'admin.macaroon')
#      if [ ${macaroonExists} -eq 0 ]; then
#        echo "FAIL --> Was not able to create macaroon"
#        echo "Please report problem."
#        exit 1
#      fi
#      echo "stopping lnd again"
#      sleep 5
#      sudo systemctl stop lnd
#    fi
# 
#     echo "Update Admin Macaroon"
#     sudo rm -r /home/admin/.lnd/data/chain/${network}/${choice}net 2>/dev/null
#     sudo mkdir /home/admin/.lnd/data/chain/${network}/${choice}net
#     sudo cp /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon /home/admin/.lnd/data/chain/${network}/${choice}net
#     sudo chown -R admin:admin /home/admin/.lnd/
# 
#     needsReboot=1
#   fi
# else
#   echo "Testnet Setting unchanged."
# fi

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

# TOR process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${runBehindTor}" != "${choice}" ]; then
  echo "TOR Setting changed .."

  # special actions if TOR is turned on
  if [ "${choice}" = "on" ]; then

    # inform user about privacy risk
    whiptail --title " PRIVACY NOTICE " --msgbox "
RaspiBlitz will now install/activate TOR & after reboot run behind it.

Please keep in mind that thru your LND node id & your previous IP history with your internet provider your lightning node could still be linked to your personal id even when running behind TOR. To unlink you from that IP history its recommended that after the switch/reboot to TOR you also use the REPAIR > RESET-LND option to create a fresh LND wallet. That might involve closing all channels & move your funds out of RaspiBlitz before that RESET-LND.
" 16 76

    # make sure AutoNAT & UPnP is off
    /home/admin/config.scripts/lnd.autonat.sh off
    /home/admin/config.scripts/network.upnp.sh off
  fi

  # change TOR
  anychange=1
  sudo /home/admin/config.scripts/internet.tor.sh ${choice}
  needsReboot=1

else
  echo "TOR Setting unchanged."
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
