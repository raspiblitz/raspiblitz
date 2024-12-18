#!/bin/bash
 
# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

echo "services default values"
if [ ${#runBehindTor} -eq 0 ]; then runBehindTor="off"; fi
if [ ${#rtlWebinterface} -eq 0 ]; then rtlWebinterface="off"; fi
if [ ${#crtlWebinterface} -eq 0 ]; then crtlWebinterface="off"; fi
if [ ${#BTCRPCexplorer} -eq 0 ]; then BTCRPCexplorer="off"; fi
if [ ${#specter} -eq 0 ]; then specter="off"; fi
if [ ${#BTCPayServer} -eq 0 ]; then BTCPayServer="off"; fi
if [ ${#ElectRS} -eq 0 ]; then ElectRS="off"; fi
if [ ${#lndmanage} -eq 0 ]; then lndmanage="off"; fi
if [ ${#joinmarket} -eq 0 ]; then joinmarket="off"; fi
if [ ${#jam} -eq 0 ]; then jam="off"; fi
if [ ${#LNBits} -eq 0 ]; then LNBits="off"; fi
if [ ${#mempoolExplorer} -eq 0 ]; then mempoolExplorer="off"; fi
if [ ${#bos} -eq 0 ]; then bos="off"; fi
if [ ${#pyblock} -eq 0 ]; then pyblock="off"; fi
if [ ${#thunderhub} -eq 0 ]; then thunderhub="off"; fi
if [ ${#sphinxrelay} -eq 0 ]; then sphinxrelay="off"; fi
if [ ${#lit} -eq 0 ]; then lit="off"; fi
if [ ${#lndg} -eq 0 ]; then lndg="off"; fi
if [ ${#whitepaper} -eq 0 ]; then whitepaper="off"; fi
if [ ${#chantools} -eq 0 ]; then chantools="off"; fi
if [ ${#helipad} -eq 0 ]; then helipad="off"; fi
if [ ${#lightningtipbot} -eq 0 ]; then lightningtipbot="off"; fi
if [ ${#fints} -eq 0 ]; then fints="off"; fi
if [ ${#lndk} -eq 0 ]; then lndk="off"; fi
if [ ${#labelbase} -eq 0 ]; then labelbase="off"; fi
if [ ${#publicpool} -eq 0 ]; then publicpool="off"; fi
if [ ${#albyhub} -eq 0 ]; then albyhub="off"; fi
if [ "${albyhub}" == "on" ] && [ $(sudo ls /etc/systemd/system/albyhub.service 2>/dev/null | grep -c 'albyhub.service') -lt 1 ]; then albyhub="off"; fi

# show select dialog
echo "run dialog ..."

OPTIONS=()

# just available for BTC
if [ "${network}" == "bitcoin" ]; then
  OPTIONS+=(ea 'BTC Electrum Rust Server' ${ElectRS})
  OPTIONS+=(pa 'BTC PayServer' ${BTCPayServer})
  OPTIONS+=(ba 'BTC RPC-Explorer' ${BTCRPCexplorer})
  OPTIONS+=(sa 'BTC Specter Desktop' ${specter})
  OPTIONS+=(aa 'BTC Mempool Space' ${mempoolExplorer})
  OPTIONS+=(ja 'BTC JoinMarket+JoininBox menu' ${joinmarket})
  OPTIONS+=(za 'BTC Jam (JoinMarket WebUI)' ${jam})
  OPTIONS+=(wa 'BTC Download Bitcoin Whitepaper' ${whitepaper})
  OPTIONS+=(ls 'BTC Labelbase' ${labelbase})
  OPTIONS+=(pp 'BTC Publicpool (Solo Mining)' ${publicpool})  
fi

# available for both LND & c-lightning
if [ "${lnd}" == "on" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(ia 'LNbits (Lightning Accounts)' ${LNBits})
  OPTIONS+=(ga 'LightningTipBot' ${lightningtipbot})
fi

# just available for LND
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(ra 'LND RTL Webinterface' ${rtlWebinterface})
  OPTIONS+=(ta 'LND ThunderHub' ${thunderhub})
  OPTIONS+=(la 'LND LIT (loop, pool, faraday)' ${lit})
  OPTIONS+=(ah 'LND AlbyHub (early access)' ${albyhub})
  OPTIONS+=(gb 'LND LNDg (auto-rebalance, auto-fees)' ${lndg})
  OPTIONS+=(oa 'LND Balance of Satoshis' ${bos})
  OPTIONS+=(ya 'LND PyBLOCK' ${pyblock})
  OPTIONS+=(ha 'LND ChannelTools (Fund Rescue)' ${chantools})
  OPTIONS+=(fa 'LND Helipad Boostagram reader' ${helipad})
  OPTIONS+=(lb 'LND LNDK (experimental BOLT 12)' ${lndk})
fi

# just available for CL
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(ca 'Core Lightning RTL Webinterface' ${crtlWebinterface})
fi

OPTIONS+=(fn 'FinTS/HBCI Interface (experimental)' ${fints})

CHOICES=$(dialog --title ' Additional Mainnet Services ' \
          --checklist ' use spacebar to activate/de-activate ' \
          27 55 20  "${OPTIONS[@]}" 2>&1 >/dev/tty)

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

# RTL process choice (LND)
choice="off"; check=$(echo "${CHOICES}" | grep -c "ra")
if [ ${check} -eq 1 ]; then choice="on"; fi

if [ "${rtlWebinterface}" != "${choice}" ]; then
  echo "RTL-lnd Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} lnd mainnet
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start RTL
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu lnd mainnet
    else
      l1="# FAIL on RTL lnd install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on lnd mainnet"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "RTL-lnd Webinterface Setting unchanged."
fi

# RTL process choice (Core Lightning)
choice="off"; check=$(echo "${CHOICES}" | grep -c "ca")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${crtlWebinterface}" != "${choice}" ]; then
  echo "RTL-cl Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} cl mainnet
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start cRTL
      echo "waiting 10 secs .."
      sleep 10
      /home/admin/config.scripts/bonus.rtl.sh menu cl mainnet
    else
      l1="# FAIL on RTL Core Lightning install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.rtl.sh on cl mainnet"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "RTL-cl Webinterface Setting unchanged."
fi

# BTC-RPC-Explorer process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ba")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCRPCexplorer}" != "${choice}" ]; then
  echo "RTL Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.btc-rpc-explorer.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start btc-rpc-explorer
      whiptail --title " Installed BTC-RPC-Explorer " --msgbox "\
The txindex may need to be created before BTC-RPC-Explorer can be active.\n
This can take ~7 hours on a RPi4 with SSD. Monitor the progress on the LCD.\n
When finished use the new 'EXPLORE' entry in Main Menu for more info.\n
" 14 50
      needsReboot=1
    else
      l1="# FAIL on BTC-RPC-Explorer install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.btc-rpc-explorer.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "BTC-RPC-Explorer Setting unchanged."
fi

# Specter Desktop process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "sa")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${specter}" != "${choice}" ]; then
  echo "Specter Desktop Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.specter.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start specter
      /home/admin/config.scripts/bonus.specter.sh menu
    else
      l1="# FAIL on Specter Desktop install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.specter.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "Specter Desktop Setting unchanged."
fi

# ElectRS process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ea")
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
      needsReboot=0
      else
        l1="# FAIL on ElectRS install #"
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "pa")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${BTCPayServer}" != "${choice}" ]; then
  echo "BTCPayServer setting changed .."

  #4049 warn if system has less than 8GB RAM
  ramGB=$(free -g | awk '/^Mem:/{print $2}')
  if [ "${choice}" =  "on" ] && [ ${ramGB} -lt 7 ]; then
    whiptail --title "Your RaspiBlitz has less than the recommended 8GB of RAM to run BTCPayServer.\nDo you really want to proceed?" 10 50 --defaultno --yes-button "Continue" --no-button "Cancel"
    if [ $? -eq 1 ]; then
      # if user choosed CANCEL just null the choice
      choice=""
    fi
  fi

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
choice="off"; check=$(echo "${CHOICES}" | grep -c "ab")
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

# CHANTOOLS process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ha")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${chantools}" != "${choice}" ]; then
  echo "chantools Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.chantools.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${chantools}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.chantools.sh menu
  fi
else
  echo "chantools setting unchanged."
fi

# Balance of Satoshis process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "oa")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "ya")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "ta")
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
      l1="# FAIL on ThunderHub install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.thunderhub.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "ThunderHub setting unchanged."
fi

# LNbits process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ia")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${LNBits}" != "${choice}" ]; then
  echo "LNbits Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh ${choice} ${lightning}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start lnbits
    sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh menu
  fi
else
  echo "LNbits setting unchanged."
fi

# LightningTipBot process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ga")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lightningtipbot}" != "${choice}" ]; then
  echo "LightningTipBot Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lightningtipbot.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start lightningtipbot
    sudo -u admin /home/admin/config.scripts/bonus.lightningtipbot.sh menu
  fi
else
  echo "LightningTipBot setting unchanged."
fi

# LIT (Lightning Terminal)
choice="off"; check=$(echo "${CHOICES}" | grep -c "la")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lit}" != "${choice}" ]; then
  echo "LIT Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lit.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start lnbits
    sudo -u admin /home/admin/config.scripts/bonus.lit.sh menu
  fi
else
  echo "LIT setting unchanged."
fi

# LNDg
choice="off"; check=$(echo "${CHOICES}" | grep -c "gb")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndg}" != "${choice}" ]; then
  echo "LNDg Setting changed .."
  anychange=1
  databasechoice=""
  isDatabase=$(sudo ls /mnt/hdd/app-data/lndg/data/db.sqlite3 2>/dev/null | grep -c 'db.sqlite3')
  if ! [ ${isDatabase} -eq 0 ]; then
    if [ "${choice}" = "off" ]; then
      whiptail --title "Delete LNDg Database?" \
      --yes-button "Keep Database" \
      --no-button "Delete Database" \
      --yesno "LNDg is getting uninstalled. If you keep the database, you will be able to reuse the data should you choose to re-install. Do you wish to keep the database?" 10 80
      if [ $? -eq 1 ]; then
        databasechoice="deletedatabase"
      fi
    else
      whiptail --title "Use Existing LNDg Database?" \
      --yes-button "Use existing database" \
      --no-button "Start a new database" \
      --yesno "LNDg is getting installed, and there is an existing database. You may use the existing database, which will include your old password and all of your old data, or you may start with a clean database. Do you wish to use the existing database?" 10 110
      if [ $? -eq 1 ]; then
        databasechoice="deletedatabase"
      fi
    fi
  fi
  sudo -u admin /home/admin/config.scripts/bonus.lndg.sh ${choice} ${databasechoice}
  if [ "${choice}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.lndg.sh menu
  fi
else
  echo "LNDg unchanged."
fi

# Helipad
choice="off"; check=$(echo "${CHOICES}" | grep -c "fa")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${helipad}" != "${choice}" ]; then
  echo "Helipad setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.helipad.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start helipad
    sudo -u admin /home/admin/config.scripts/bonus.helipad.sh menu
  fi
else
  echo "Helipad setting unchanged."
fi

# LNDK
choice="off"; check=$(echo "${CHOICES}" | grep -c "lb")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndk}" != "${choice}" ]; then
  echo "LNDK Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lndk.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    whiptail --title " Installed LNDK" --msgbox "\
LNDK was installed.\n
" 10 45
  fi
else
  echo "LNDK Setting unchanged."
fi

# JoinMarket process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ja")
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

# Jam process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "za")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${jam}" != "${choice}" ]; then
  echo "Jam setting changed .."
  # check if TOR is installed
  source /mnt/hdd/raspiblitz.conf
  if [ "${choice}" =  "on" ] && [ "${runBehindTor}" = "off" ]; then
    whiptail --title " Use Tor with Jam" --msgbox "\
It is highly recommended to use Tor with Jam.\n
Please activate TOR in SERVICES first.\n
Then try activating Jam again in SERVICES.\n
" 13 42
  else
    anychange=1
    sudo /home/admin/config.scripts/bonus.jam.sh ${choice}
    errorOnInstall=$?
    if [ "${choice}" =  "on" ]; then
      if [ ${errorOnInstall} -eq 0 ]; then
         sudo /home/admin/config.scripts/bonus.jam.sh menu
      else
        whiptail --title 'FAIL' --msgbox "Jam installation is cancelled\nTry again from the menu or install from the terminal with:\nsudo /home/admin/config.scripts/bonus.jam.sh on" 9 65
      fi
    fi
  fi
else
  echo "Jam not changed."
fi

# Mempool process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "aa")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${mempoolExplorer}" != "${choice}" ]; then
  echo "Mempool Explorer settings changed .."
  anychange=1
  /home/admin/config.scripts/bonus.mempool.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start mempool
      whiptail --title " Installed Mempool Space " --msgbox "\
The txindex may need to be created before Mempool can be active.\n
This can take ~7 hours on a RPi4 with SSD. Monitor the progress on the LCD.\n
When finished use the new 'MEMPOOL' entry in Main Menu for more info.\n
" 14 50
    else
      l1="# FAIL on Mempool Explorer install #"
      l2="Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/bonus.mempool.sh on"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "Mempool Explorer Setting unchanged."
fi

# Whitepaper process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "wa")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${whitepaper}" != "${choice}" ]; then
  echo "Whitepaper setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.whitepaper.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${whitepaper}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.whitepaper.sh menu
  fi
else
  echo "Whitepaper setting unchanged."
fi

# labelbase process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ls")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${labelbase}" != "${choice}" ]; then
  echo "Labelbase setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.labelbase.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${labelbase}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.labelbase.sh menu
  fi
else
  echo "Labelbase setting unchanged."
fi

# publicpool process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "pp")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${publicpool}" != "${choice}" ]; then
  echo "Publicpool setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.publicpool.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${publicpool}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.publicpool.sh menu
  fi
else
  echo "Publicpool setting unchanged."
fi

# albyhub process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "ah")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${albyhub}" != "${choice}" ]; then
  echo "AlbyHub setting changed .."
  anychange=1
  if [ "${choice}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.albyhub.sh on
    sudo -u admin /home/admin/config.scripts/bonus.albyhub.sh menu
  else
      whiptail --title "Delete Database?" \
      --yes-button "Keep Database" \
      --no-button "Delete Database" \
      --yesno "AlbyHub is getting uninstalled. If you keep the database, you will be able to reuse the data should you choose to re-install. Do you wish to keep the database?" 10 80
      if [ $? -eq 1 ]; then
        echo "# Uninstalling AlbyHub AND DELETING DATA ..."
        sudo -u admin /home/admin/config.scripts/bonus.albyhub.sh off delete-data
      else
        echo "# Uninstalling AlbyHub but keeping data ..."
        sudo -u admin /home/admin/config.scripts/bonus.albyhub.sh off
      fi
  fi
else
  echo "AlbyHub setting unchanged."
fi

# fints process choice  
choice="off"; check=$(echo "${CHOICES}" | grep -c "fn")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${fints}" != "${choice}" ]; then
  echo "fints setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.fints.sh ${choice}
else
  echo "fints setting unchanged."
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
