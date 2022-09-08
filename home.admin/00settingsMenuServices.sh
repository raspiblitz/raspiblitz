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
if [ ${#homer} -eq 0 ]; then homer="off"; fi
if [ ${#sparko} -eq 0 ]; then sparko="off"; fi
if [ ${#spark} -eq 0 ]; then spark="off"; fi
if [ ${#tallycoinConnect} -eq 0 ]; then tallycoinConnect="off"; fi
if [ ${#helipad} -eq 0 ]; then helipad="off"; fi
if [ ${#bitcoinminds} -eq 0 ]; then bitcoinminds="off"; fi
if [ ${#squeaknode} -eq 0 ]; then squeaknode="off"; fi
if [ ${#itchysats} -eq 0 ]; then itchysats="off"; fi

# show select dialog
echo "run dialog ..."

OPTIONS=()

# just available for BTC
if [ "${network}" == "bitcoin" ]; then
  OPTIONS+=(e 'BTC Electrum Rust Server' ${ElectRS})
  OPTIONS+=(p 'BTC PayServer' ${BTCPayServer})
  OPTIONS+=(b 'BTC RPC-Explorer' ${BTCRPCexplorer})
  OPTIONS+=(s 'BTC Specter Desktop' ${specter})
  OPTIONS+=(a 'BTC Mempool Space' ${mempoolExplorer})
  OPTIONS+=(j 'BTC JoinMarket+JoininBox menu' ${joinmarket})
  OPTIONS+=(w 'BTC Download Bitcoin Whitepaper' ${whitepaper})
  OPTIONS+=(v 'BTC Install BitcoinMinds.org' ${bitcoinminds})
  OPTIONS+=(u 'BTC Install ItchySats' ${itchysats})
fi

# available for both LND & c-lightning
if [ "${lnd}" == "on" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(i 'LNbits (Lightning Accounts)' ${LNBits})
fi

# just available for LND
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(r 'LND RTL Webinterface' ${rtlWebinterface})
  OPTIONS+=(t 'LND ThunderHub' ${thunderhub})
  OPTIONS+=(l 'LND LIT (loop, pool, faraday)' ${lit})
  OPTIONS+=(g 'LND LNDg (auto-rebalance, auto-fees)' ${lndg})
  OPTIONS+=(o 'LND Balance of Satoshis' ${bos})
  OPTIONS+=(y 'LND PyBLOCK' ${pyblock})
  OPTIONS+=(h 'LND ChannelTools (Fund Rescue)' ${chantools})
  OPTIONS+=(x 'LND Sphinx-Relay' ${sphinxrelay})
  OPTIONS+=(f 'LND Helipad Boostagram reader' ${helipad})
  OPTIONS+=(d 'LND Tallycoin Connect' ${tallycoinConnect})
  #OPTIONS+=(q 'LND Squeaknode' ${squeaknode})
fi

# just available for CL
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(c 'Core Lightning RTL Webinterface' ${crtlWebinterface})
  OPTIONS+=(k 'Core Lightning Sparko WebWallet' ${sparko})
  OPTIONS+=(n 'Core Lightning Spark Wallet' ${spark})
fi

OPTIONS+=(m 'Homer Dashboard' ${homer})

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
choice="off"; check=$(echo "${CHOICES}" | grep -c "r")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "c")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${crtlWebinterface}" != "${choice}" ]; then
  echo "RTL-cl Webinterface Setting changed .."
  anychange=1
  /home/admin/config.scripts/bonus.rtl.sh ${choice} cl mainnet
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      sudo systemctl start RTL
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "b")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "s")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "ä")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "h")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "i")
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

# LIT (Lightning Terminal)
choice="off"; check=$(echo "${CHOICES}" | grep -c "l")
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "g")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${lndg}" != "${choice}" ]; then
  echo "LNDg Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.lndg.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.lndg.sh menu
  fi
else
  echo "LNDg unchanged."
fi

# Sphinx Relay
choice="off"; check=$(echo "${CHOICES}" | grep -c "x")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${sphinxrelay}" != "${choice}" ]; then
  echo "Sphinx-Relay Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.sphinxrelay.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    echo "Giving service 1 minute to start up ... (please wait) ..."
    sleep 60
    whiptail --title " Installed Sphinx Server" --msgbox "\
Sphinx Server was installed.\n
Use the new 'SPHINX' entry in Main Menu for more info.\n
" 10 35
  fi
else
  echo "Sphinx Relay unchanged."
fi

# Helipad
choice="off"; check=$(echo "${CHOICES}" | grep -c "f")
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

# Tallycoin
choice="off"; check=$(echo "${CHOICES}" | grep -c "d")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${tallycoinConnect}" != "${choice}" ]; then
  echo "Tallycoin Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.tallycoin-connect.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    whiptail --title " Installed Tallycoin-Connect" --msgbox "\
Tallycoin-Connect was installed.\n
Use the new 'TALLY' entry in Main Menu for more info.\n
" 10 45
  fi
else
  echo "Tallycoin Setting unchanged."
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
choice="off"; check=$(echo "${CHOICES}" | grep -c "w")
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

# Homer process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "m")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${homer}" != "${choice}" ]; then
  echo "Homer settings changed .."
  anychange=1
  /home/admin/config.scripts/bonus.homer.sh ${choice}
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    whiptail --title " Installed Homer" --msgbox "\
Homer was installed.\n
Use the new 'Homer' entry in Main Menu for more info.\n
" 10 35
  fi
else
  echo "Homer Setting unchanged."
fi

# BitcoinMinds process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "v")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${bitcoinminds}" != "${choice}" ]; then
  echo "BitcoinMinds setting changed."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.bitcoinminds.sh ${choice}
  source /mnt/hdd/raspiblitz.conf
  if [ "${bitcoinminds}" =  "on" ]; then
    sudo -u admin /home/admin/config.scripts/bonus.bitcoinminds.sh menu
  fi
else
  echo "BitcoinMinds setting unchanged."
fi

# sparko process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "k")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${sparko}" != "${choice}" ]; then
  echo "# Sparko on mainnet Setting changed .."
  anychange=1
  /home/admin/config.scripts/cl-plugin.sparko.sh ${choice} mainnet
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      /home/admin/config.scripts/cl-plugin.sparko.sh menu mainnet
    else
      l1="# FAIL on Sparko on mainnet install #"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cl-plugin.sparko.sh on mainnet"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# Sparko on mainnet Setting unchanged."
fi

# spark wallet process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "n")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${spark}" != "${choice}" ]; then
  echo "# Spark Wallet on mainnet Setting changed .."
  anychange=1
  /home/admin/config.scripts/cl.spark.sh ${choice} mainnet
  errorOnInstall=$?
  if [ "${choice}" =  "on" ]; then
    if [ ${errorOnInstall} -eq 0 ]; then
      /home/admin/config.scripts/cl.spark.sh menu mainnet
    else
      l1="# FAIL on Spark Wallet on mainnet install #"
      l2="# Try manual install on terminal after reboot with:"
      l3="/home/admin/config.scripts/cl.spark.sh on mainnet"
      dialog --title 'FAIL' --msgbox "${l1}\n${l2}\n${l3}" 7 65
    fi
  fi
else
  echo "# Spark Wallet on mainnet Setting unchanged."
fi

# squeaknode process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "q")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${squeaknode}" != "${choice}" ]; then
  echo "squeaknode Setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.squeaknode.sh ${choice}
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start squeaknode
    sudo -u admin /home/admin/config.scripts/bonus.squeaknode.sh menu
  fi
else
  echo "squeaknode setting unchanged."
fi

# ItchySats process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "u")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${itchysats}" != "${choice}" ]; then
  echo "ItchySats setting changed .."
  anychange=1
  sudo -u admin /home/admin/config.scripts/bonus.itchysats.sh ${choice} --download
  if [ "${choice}" =  "on" ]; then
    sudo systemctl start itchysats
    sudo -u admin /home/admin/config.scripts/bonus.itchysats.sh menu
  fi
else
  echo "ItchySats setting unchanged."
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
