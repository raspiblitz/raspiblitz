#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#autoPilot} -eq 0 ]; then autoPilot="off"; fi
if [ ${#autoUnlock} -eq 0 ]; then autoUnlock="off"; fi
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#chain} -eq 0 ]; then chain="main"; fi
if [ ${#autoNatDiscovery} -eq 0 ]; then autoNatDiscovery="off"; fi
if [ ${#networkUPnP} -eq 0 ]; then networkUPnP="off"; fi
if [ ${#touchscreen} -eq 0 ]; then touchscreen=0; fi
if [ ${#lcdrotate} -eq 0 ]; then lcdrotate=0; fi

echo "map chain to on/off"
chainValue="off"
if [ "${chain}" = "test" ]; then chainValue="on"; fi

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
tochscreenMenu='off'
if [ ${touchscreen} -gt 0 ]; then 
  tochscreenMenu='on'
fi

echo "check autopilot by lnd.conf"
lndAutoPilotOn=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'autopilot.active=1')
if [ ${lndAutoPilotOn} -eq 1 ]; then
  autoPilot="on"
else
  autoPilot="off"
fi

# show select dialog
echo "run dialog ..."

if [ "${runBehindTor}" = "on" ]; then
CHOICES=$(dialog --title ' Additional Services ' --checklist ' use spacebar to activate/de-activate ' 15 45 8 \
1 'Channel Autopilot' ${autoPilot} \
2 'Testnet' ${chainValue} \
3 ${dynDomainMenu} ${domainValue} \
4 'Run behind TOR' ${runBehindTor} \
5 'RTL Webinterface' ${rtlWebinterface} \
6 'LND Auto-Unlock' ${autoUnlock} \
9 'Touchscreen' ${tochscreenMenu} \
r 'LCD Rotate' ${lcdrotateMenu} \
2>&1 >/dev/tty)
else
CHOICES=$(dialog --title ' Additional Services ' --checklist ' use spacebar to activate/de-activate ' 16 45 9 \
1 'Channel Autopilot' ${autoPilot} \
2 'Testnet' ${chainValue} \
3 ${dynDomainMenu} ${domainValue} \
4 'Run behind TOR' ${runBehindTor} \
5 'RTL Webinterface' ${rtlWebinterface} \
6 'LND Auto-Unlock' ${autoUnlock} \
7 'BTC UPnP (AutoNAT)' ${networkUPnP} \
8 'LND UPnP (AutoNAT)' ${autoNatDiscovery} \
9 'Touchscreen' ${tochscreenMenu} \
r 'LCD Rotate' ${lcdrotateMenu} \
2>&1 >/dev/tty)
fi

dialogcancel=$?
echo "done dialog"
clear

# check if user canceled dialog
echo "dialogcancel(${dialogcancel})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
fi

needsReboot=0
anychange=0

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "1")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ]; then
  echo "Autopilot Setting changed .."
  anychange=1
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
    anychange=1
    sudo /home/admin/config.scripts/network.chain.sh ${choice}net
    walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${choice}net/wallet.db 2>/dev/null | grep -c 'wallet.db')
    if [ ${walletExists} -eq 0 ]; then
      echo "Need to creating a new wallet ... wait 20secs"
      sudo systemctl start lnd
      sleep 20
      tryAgain=1
      while [ ${tryAgain} -eq 1 ]
        do
          echo "****************************************************************************"
          echo "Creating a new LND Wallet for ${network}/${choice}net"
          echo "****************************************************************************"
          echo "A) For 'Wallet Password' use your PASSWORD C --> !! minimum 8 characters !!"
          echo "B) Answere 'n' because you dont have a 'cipher seed mnemonic' (24 words) yet" 
          echo "C) For 'passphrase' to encrypt your 'cipher seed' use PASSWORD D (optional)"
          echo "****************************************************************************"
          sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net create 2>error.out
          error=`sudo cat error.out`
          if [ ${#error} -eq 0 ]; then
            sleep 2  
            # WIN
            tryAgain=0
            echo "!!! Make sure to write down the 24 words (cipher seed mnemonic) !!!"
            echo "If you are ready. Press ENTER."
          else
            # FAIL
            tryAgain=1
            echo "!!! FAIL ---> SOMETHING WENT WRONG !!!"
            echo "${error}"
            echo "Press ENTER to retry ... or CTRL-c to EXIT"
          fi
          read key
        done
      echo "Check for Macaroon .. (10sec)"
      sleep 10
      macaroonExists=$(sudo ls /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon | grep -c 'admin.macaroon')
      if [ ${macaroonExists} -eq 0 ]; then
        echo "*** PLEASE UNLOCK your wallet with PASSWORD C to create macaroon"
        lncli unlock 2>/dev/null
        sleep 6
      fi
      macaroonExists=$(sudo ls /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon | grep -c 'admin.macaroon')
      if [ ${macaroonExists} -eq 0 ]; then
        echo "FAIL --> Was not able to create macaroon"
        echo "Please report problem."
        exit 1
      fi
      echo "stopping lnd again"
      sleep 5
      sudo systemctl stop lnd
    fi

    echo "Update Admin Macaroon"
    sudo rm -r /home/admin/.lnd/data/chain/${network}/${choice}net 2>/dev/null
    sudo mkdir /home/admin/.lnd/data/chain/${network}/${choice}net
    sudo cp /home/bitcoin/.lnd/data/chain/${network}/${choice}net/admin.macaroon /home/admin/.lnd/data/chain/${network}/${choice}net
    sudo chown -R admin:admin /home/admin/.lnd/
    
    needsReboot=1
  fi
else 
  echo "Testnet Setting unchanged."
fi

# Dynamic Domain
choice="off"; check=$(echo "${CHOICES}" | grep -c "3")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "7")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "8")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "4")
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

# RTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "5")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${rtlWebinterface}" != "${choice}" ]; then
  echo "RTL Webinterface Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/bonus.rtl.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
      l1="RTL web service will be ready AFTER NEXT REBOOT:"
      l2="Try to open the following URL in your local web browser"
      l3="and login with your PASSWORD B."
      l4="---> http://${localip}:3000"
      dialog --title 'OK' --msgbox "${l1}\n${l2}\n${l3}\n${l4}" 11 65
    else
      l1="!!! FAIL on RTL install !!!"
      l2="Try manual install on terminal after rebootwith:"
      l3="sudo /home/admin/config.scripts/bonus.rtl.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 10 65
    fi
  fi
  needsReboot=1
else
  echo "RTL Webinterface Setting unchanged."
fi

# LND Auto-Unlock
choice="off"; check=$(echo "${CHOICES}" | grep -c "6")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoUnlock}" != "${choice}" ]; then
  echo "LND Autounlock Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/lnd.autounlock.sh ${choice}
  l1="AUTO-UNLOCK IS NOW OFF"
  if [ "${choice}" = "on" ]; then
    l1="AUTO-UNLOCK IS NOW ACTIVE"
  fi  
  l2="-------------------------"
  l3="mobile/external wallets may need reconnect"
  l4="possible change in macaroon / TLS cert"
  dialog --title 'OK' --msgbox "${l1}\n${l2}\n${l3}\n${l4}" 11 60
  needsReboot=1
else
  echo "LND Autounlock Setting unchanged."
fi

# touchscreen
choice="0"; check=$(echo "${CHOICES}" | grep -c "9")
if [ ${check} -eq 1 ]; then choice="1"; fi
if [ "${touchscreen}" != "${choice}" ]; then
  echo "Touchscreen Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.touchscreen.sh ${choice}
  needsReboot=1
else
  echo "Touchscreen Setting unchanged."
fi

# lcd rotate
choice="0"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="1"; fi
if [ "${lcdrotate}" != "${choice}" ]; then
  echo "LCD Rotate Setting changed .."
  anychange=1
  sudo /home/admin/config.scripts/blitz.lcdrotate.sh ${choice}
  needsReboot=1
else
  echo "LCD Rotate Setting unchanged."
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
   sudo shutdown -r now
fi
