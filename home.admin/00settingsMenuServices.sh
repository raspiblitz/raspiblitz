#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#loop} -eq 0 ]; then loop="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#BTCRPCexplorer} -eq 0 ]; then BTCRPCexplorer="off"; fi
if [ ${#specter} -eq 0 ]; then specter="off"; fi
if [ ${#BTCPayServer} -eq 0 ]; then BTCPayServer="off"; fi
if [ ${#ElectRS} -eq 0 ]; then ElectRS="off"; fi
if [ ${#lndmanage} -eq 0 ]; then lndmanage="off"; fi
if [ ${#joinmarket} -eq 0 ]; then joinmarket="off"; fi
if [ ${#LNBits} -eq 0 ]; then LNBits="off"; fi
if [ ${#mempoolExplorer} -eq 0 ]; then mempoolExplorer="off"; fi
if [ ${#faraday} -eq 0 ]; then faraday="off"; fi
if [ ${#bos} -eq 0 ]; then bos="off"; fi
if [ ${#pyblock} -eq 0 ]; then pyblock="off"; fi
if [ ${#thunderhub} -eq 0 ]; then thunderhub="off"; fi
if [ ${#pool} -eq 0 ]; then pool="off"; fi
if [ ${#sphinxrelay} -eq 0 ]; then sphinxrelay="off"; fi

# show select dialog
echo "run dialog ..."

OPTIONS=()
OPTIONS+=(e 'Electrum Rust Server' ${ElectRS})
OPTIONS+=(r 'RTL Webinterface' ${rtlWebinterface})
OPTIONS+=(t 'ThunderHub' ${thunderhub})
OPTIONS+=(p 'BTCPayServer' ${BTCPayServer})
OPTIONS+=(i 'LNbits' ${LNBits})
OPTIONS+=(b 'BTC-RPC-Explorer' ${BTCRPCexplorer})
OPTIONS+=(s 'Cryptoadvance Specter' ${specter})
OPTIONS+=(a 'Mempool Explorer' ${mempoolExplorer})
OPTIONS+=(j 'JoinMarket' ${joinmarket})
OPTIONS+=(l 'Lightning Loop' ${loop})
OPTIONS+=(o 'Balance of Satoshis' ${bos})
OPTIONS+=(f 'Faraday' ${faraday})
OPTIONS+=(c 'Lightning Pool' ${pool})
OPTIONS+=(y 'PyBLOCK' ${pyblock})
OPTIONS+=(m 'lndmanage' ${lndmanage})
OPTIONS+=(x 'Sphinx-Relay' ${sphinxrelay})

CHOICES=$(dialog --title ' Additional Services ' --checklist ' use spacebar to activate/de-activate ' 20 45 12  "${OPTIONS[@]}" 2>&1 >/dev/tty)

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

# LOOP process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${loop}" != "${choice}" ]; then
  echo "Loop Setting changed .."
  anychange=1
  needsReboot=1 # always reboot so that RTL gets restarted to show/hide support loop
  /home/admin/config.scripts/bonus.loop.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      # check macaroons and fix missing
      /home/admin/config.scripts/lnd.credential.sh check
      sudo systemctl start loopd
      /home/admin/config.scripts/bonus.loop.sh menu
    else
      l1="FAILED to install Lightning LOOP"
      l2="Try manual install in the terminal with:"
      l3="/home/admin/config.scripts/bonus.loop.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "Loop Setting unchanged."
fi

# RTL process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "r")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${rtlWebinterface}" != "${choice}" ]; then
  echo "RTL Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start RTL
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu
    else
      l1="!!! FAIL on RTL install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "RTL Webinterface Setting unchanged."
fi

# BTC-RPC-Explorer process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "b")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCRPCexplorer}" != "${choice}" ]; then
  echo "RTL Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.btc-rpc-explorer.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo sytemctl start btc-rpc-explorer
      whiptail --title " Installed BTC-RPC-Explorer " --msgbox "\
The txindex may need to be created before BTC-RPC-Explorer can be active.\n
This can take ~7 hours on a RPi4 with SSD. Monitor the progress on the LCD.\n
When finished use the new 'EXPLORE' entry in Main Menu for more info.\n
" 14 50
      needsReboot=1
    else
      l1="!!! FAIL on BTC-RPC-Explorer install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.btc-rpc-explorer.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "BTC-RPC-Explorer Setting unchanged."
fi

# cryptoadvance Specter process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "s")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${specter}" != "${choice}" ]; then
  echo "Cryptoadvance Specter Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.cryptoadvance-specter.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start cryptoadvance-specter
      /home/admin/config.scripts/bonus.cryptoadvance-specter.sh menu
    else
      l1="!!! FAIL on Cryptoadvance Specter install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.cryptoadvance-specter.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "Cryptoadvance Specter Setting unchanged."
fi

# ElectRS process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "e")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${ElectRS}" != "${choice}" ]; then
  echo "ElectRS Setting changed .."
  anychange=1
  extraparameter=""
  if [ "${choice}" =  "on" ]; then
    # check on HDD size
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
    if [ ${hddGigaBytes} -lt 800 ]; then
      whiptail --title " HDD/SSD TOO SMALL " --msgbox "\
Since v1.5 we recommend at least a 1TB HDD/SSD if you want to run ElectRS.\n
This is due to the eletcrum index that will grow over time and needs space.\n
To migrate to a bigger HDD/SSD check RaspiBlitz README on 'migration'.\n
" 14 50
    else
      /home/admin/config.scripts/bonus.electrs.sh on ${extraparameter}
      errorOnInstall=$?
      if [ ${errorOnInstall} -eq 0 ]; then
        sudo systemctl start electrs
        whiptail --title " Installed ElectRS Server " --msgbox "\
The index database needs to be created before Electrum Server can be used.\n
This can take hours/days depending on your RaspiBlitz. Monitor the progress on the LCD.\n
When finished use the new 'ELECTRS' entry in Main Menu for more info.\n
" 14 50
      needsReboot=1
      else
        l1="!!! FAIL on ElectRS install !!!"
        l2="Try manual install on terminal after reboot with:"
        l3="/home/admin/config.scripts/bonus.electrs.sh on"
        dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
      fi
    fi
  fi
  if [ "${choice}" =  "off" ]; then
	  whiptail --title "Delete Electrum Index?" \
    --yes-button "Keep Index" \
    --no-button "Delete Index" \
    --yesno "ElectRS is getting uninstalled. Do you also want to delete the Electrum Index? It contains no important data, but can take multiple hours to rebuild if needed again." 10 60
	  if [ $? -eq 1 ]; then
      extraparameter="deleteindex"
	  fi
    /home/admin/config.scripts/bonus.electrs.sh off ${extraparameter}
  fi

else
  echo "ElectRS Setting unchanged."
fi

# BTCPayServer process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "p")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCPayServer}" != "${choice}" ]; then
  echo "BTCPayServer setting changed .."
  # check if TOR is installed
  source /mnt/hdd/raspiblitz.conf
  if [ "${choice}" =  "on" ] && [ "${runBehindTor}" = "off" ]; then
    whiptail --title " BTCPayServer needs TOR " --msgbox "\
At the moment the BTCPayServer on the RaspiBlitz needs TOR.\n
Please activate TOR in SERVICES first.\n
Then try activating BTCPayServer again in SERVICES.\n
" 13 42
  else
    anychange=1
    /home/admin/config.scripts/bonus.btcpayserver.sh ${choice} tor
    errorOnInstall=$?
    if [ "${choice}" =  "on" ]; then
      if [ ${errorOnInstall} -eq 0 ]; then
        source /home/btcpay/.btcpayserver/Main/settings.config
        whiptail --title " Installed BTCPay Server " --msgbox "\
BTCPay server was installed.\n
Use the new 'BTCPay' entry in Main Menu for more info.\n
" 10 35
      else
        l1="BTCPayServer installation is cancelled"
        l2="Try again from the menu or install from the terminal with:"
        l3="/home/admin/config.scripts/bonus.btcpayserver.sh on"
        dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
      fi
    fi
  fi
else
  echo "BTCPayServer setting not changed."
fi

# LNDMANAGE process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "m")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndmanage}" != "${choice}" ]; then
  echo "lndmanage Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lndmanage.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${lndmanage}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.lndmanage.sh menu
  fi
else
  echo "lndmanage setting unchanged."
fi

# FARADAY process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "f")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${faraday}" != "${choice}" ]; then
  echo "faraday Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.faraday.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${faraday}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.faraday.sh menu
  fi
else
  echo "faraday setting unchanged."
fi


# Balance of Satoshis process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "o")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${bos}" != "${choice}" ]; then
  echo "Balance of Satoshis Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.bos.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${bos}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.bos.sh menu
  fi
else
  echo "Balance of Satoshis setting unchanged."
fi

# PyBLOCK process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "y")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${pyblock}" != "${choice}" ]; then
  echo "PyBLOCK Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.pyblock.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${pyblock}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.pyblock.sh menu
  fi
else
  echo "PyBLOCK setting unchanged."
fi

# thunderhub process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${thunderhub}" != "${choice}" ]; then
  echo "ThunderHub Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.thunderhub.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start thunderhub
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.thunderhub.sh menu
    else
      l1="!!! FAIL on ThunderHub install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.thunderhub.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "ThunderHub setting unchanged."
fi

# LNbits process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "i")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${LNBits}" != "${choice}" ]; then
  echo "LNbits Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start lnbits
    sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh menu
  fi
else
  echo "LNbits setting unchanged."
fi

# Lightning Pool
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${pool}" != "${choice}" ]; then
  echo "Pool Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.pool.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.pool.sh menu
  fi
else
  echo "Pool setting unchanged."
fi

# Sphinx Relay
choice="off"; check=$(echo "${CHOICES}" | grep -c "x")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${sphinxrelay}" != "${choice}" ]; then
  echo "Sphinx-Relay Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.sphinxrelay.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    whiptail --title " Installed Sphinx Server" --msgbox "\
Sphinx Server was installed.\n
Use the new 'SPHINX' entry in Main Menu for more info.\n
" 10 35
  fi
else
  echo "Sphinx Relay unchanged."
fi

# JoinMarket process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "j")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${joinmarket}" != "${choice}" ]; then
  echo "JoinMarket setting changed .."
  # check if TOR is installed
  source /mnt/hdd/raspiblitz.conf
  if [ "${choice}" =  "on" ] && [ "${runBehindTor}" = "off" ]; then
    whiptail --title " Use Tor with JoinMarket" --msgbox "\
It is highly recommended to use Tor with JoinMarket.\n
Please activate TOR in SERVICES first.\n
Then try activating JoinMarket again in SERVICES.\n
" 13 42
  else
    anychange=1
    sudo /home/admin/config.scripts/bonus.joinmarket.sh ${choice}
    errorOnInstall=$?
    if [ "${choice}" =  "on" ]; then
      if [ ${errorOnInstall} -eq 0 ]; then
         sudo /home/admin/config.scripts/bonus.joinmarket.sh menu
      else
        whiptail --title 'FAIL' --msgbox "JoinMarket installation is cancelled\nTry again from the menu or install from the terminal with:\nsudo /home/admin/config.scripts/bonus.joinmarket.sh on" 9 65
      fi
    fi
  fi
else
  echo "JoinMarket not changed."
fi

# Mempool process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "a")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${mempoolExplorer}" != "${choice}" ]; then
  echo "Mempool Explorer settings changed .."
  anychange=1
  /home/admin/config.scripts/bonus.mempool.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo sytemctl start mempool
      whiptail --title " Installed Mempool Space " --msgbox "\
The txindex may need to be created before Mempool can be active.\n
This can take ~7 hours on a RPi4 with SSD. Monitor the progress on the LCD.\n
When finished use the new 'MEMPOOL' entry in Main Menu for more info.\n
" 14 50
    else
      l1="!!! FAIL on Mempool Explorer install !!!"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.mempool.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "Mempool Explorer Setting unchanged."
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
   sudo /home/admin/XXshutdown.sh reboot
fi
