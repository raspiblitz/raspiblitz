#!/bin/bash

# CHECK WHAT IS ALREADY WORKING
# check list from top down - so ./10setupBlitz.sh
# and re-enters the setup process at the correct spot
# in case it got interrupted
echo "checking setup script"

# INFOFILE on SD - state data from bootstrap & setup
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

echo "network(${network})"
echo "chain(${chain})"
echo "setupStep(${setupStep})"

if [ ${#network} -eq 0 ]; then
  echo "FAIL: Something is wrong. There is no value for network in ${infoFile}."
  echo "Should be at least default value. EXIT"
  exit 1
fi

# if no setup step in info file init with 0
if [ ${#setupStep} -eq 0 ];then
  echo "Init setupStep=0"
  echo "setupStep=0" >> ${infoFile}
  setupStep=0
fi

# check if LND needs re-setup
if [ ${setupStep} -gt 79 ];then
  source <(sudo /home/admin/config.scripts/lnd.check.sh basic-setup)
  if [ ${wallet} -eq 0 ] || [ ${macaroon} -eq 0 ] || [ ${config} -eq 0 ] || [ ${tls} -eq 0 ]; then
      echo "WARN: LND needs re-setup"
      sudo /home/admin/70initLND.sh
      exit 0
  fi
fi

# if setup if ready --> REBOOT
if [ ${setupStep} -gt 89 ];then
  echo "FINISH by setupstep(${setupStep})"
  sleep 3
  sudo /home/admin/90finishSetup.sh
  sudo /home/admin/95finalSetup.sh
  exit 0
fi

# check if lightning is running
lndRunning=$(systemctl status lnd.service 2>/dev/null | grep -c running)
if [ ${lndRunning} -eq 1 ]; then
  
  echo "LND is running ..."
  sleep 1

  # check if LND wallet exists and if locked
  walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep wallet.db -c)
  walletLocked=0
  # only when a wallet exists - it can be locked
  if [ ${walletExists} -eq 1 ];then
    echo "lnd wallet exists ... checking if locked"
    sleep 2
    walletLocked=$(sudo -u bitcoin /usr/local/bin/lncli getinfo 2>&1 | grep -c unlock)
  fi
  if [ ${walletLocked} -gt 0 ]; then
    # LND wallet is locked
    /home/admin/config.scripts/lnd.unlock.sh
    /home/admin/10setupBlitz.sh
    exit 0
  fi

  # check if blockchain still syncing (during sync sometimes CLI returns with error at this point)
  chainInfo=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | grep 'initialblockdownload')
  chainSyncing=1
  if [ ${#chainInfo} -gt 0 ];then
    echo "check chaininfo" 
    chainSyncing=$(echo "${chainInfo}" | grep "true" -c)
  else 
    echo "chaininfo is zero" 
  fi
  if [ ${chainSyncing} -eq 1 ]; then
    echo "Sync Chain ..."
    sleep 3
    /home/admin/70initLND.sh
    exit 0
  fi

  # check if lnd is scanning blockchain
  lndInfo=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} getinfo 2>/dev/null | grep "synced_to_chain")
  lndSyncing=1
  if [ ${#lndInfo} -gt 0 ];then
    lndSyncing=$(echo "${chainInfo}" | grep "false" -c)
  fi
  if [ ${lndSyncing} -eq 1 ]; then
    echo "Sync LND ..." 
    sleep 3
    /home/admin/70initLND.sh
    exit 0
  fi

  # if unlocked, blockchain synced and LND synced to chain .. finish Setup
  echo "FINSIH ... "
  sleep 3
  sudo /home/admin/90finishSetup.sh
  sudo /home/admin/95finalSetup.sh
  exit 0

fi #end - when lighting is running

# check if bitcoin is running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  # double check
  seconds=120
  if [ ${setupStep} -lt 60 ]; then
    seconds=10
  fi
  dialog --pause "  Double checking for ${network}d - please wait .." 8 58 ${seconds}
  clear
  bitcoinRunning=$(${network}-cli getblockchaininfo 2>/dev/null | grep "initialblockdownload" -c)
else
  echo "${network} is running"  
fi
if [ ${bitcoinRunning} -eq 1 ]; then
  echo "OK - ${network}d is running"
  echo "Next step run Lightning"
  /home/admin/70initLND.sh
  exit 1
else
 echo "${network} still not running"  
fi #end - when bitcoin is running

# --- so neither bitcoin or lnd or running yet --> find the earlier step in the setup process:

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status ${network})
if [ ${#error} -gt 0 ]; then
  echo "# FAIL blitz.datadrive.sh status --> ${error}"
  echo "# Please report issue to the raspiblitz github."
  exit 1
fi

# check if HDD is auto-mounted
if [ ${isMounted} -eq 1 ]; then
  
  # FAILSAFE: check if raspiblitz.conf is available
  configExists=$(ls /mnt/hdd/raspiblitz.conf | grep -c '.conf')
  if [ ${configExists} -eq 0 ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "FAIL: /mnt/hdd/raspiblitz.conf should exists at this point, but not found!"
    echo "Please report to: https://github.com/rootzoll/raspiblitz/issues/293"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Press ENTER to EXIT."
    read key
    exit 1
  fi

  # are there any signs of blockchain data and activity
  # setup running with admin user, but has no permission to read /mnt/hdd/bitcoin/blocks/, sudo needed
  blockchainDataExists=$(sudo ls /mnt/hdd/${network}/blocks 2>/dev/null | grep -c '.dat')
  configExists=$(sudo ls /mnt/hdd/${network}/${network}.conf | grep -c '.conf')

  if [ ${blockchainDataExists} -gt 0 ]; then
    if [ ${configExists} -eq 1 ]; then
      /home/admin/XXdebugLogs.sh
      echo "UNKOWN STATE - there is blockchain data config, but blockchain service is not running"
      echo "It seems that something went wrong during sync/download/copy of the blockchain."
      echo "Or something with the config is not correct."
      echo "Sometimes a reboot helps - use command: restart"
      echo "Or try to repair blockchain - use command: repair"
      exit 1
    else 
      echo "Got mounted blockchain, but no config and running service yet --> finish HDD"
      /home/admin/60finishHDD.sh
      exit 1
    fi
  fi

  # HDD is empty - get Blockchain

  # detect hardware version of RaspberryPi
  # https://www.unixtutorial.org/command-to-confirm-raspberry-pi-model
  raspberryPi=$(cat /proc/device-tree/model | cut -d " " -f 3 | sed 's/[^0-9]*//g')
  if [ ${#raspberryPi} -eq 0 ]; then
    raspberryPi=0
  fi

  # Bitcoin on older/weak RaspberryPi3 (LEGACY)
  if [ ${network} = "bitcoin" ] && [ ${raspberryPi} -eq 3 ]; then
    echo "Bitcoin-RP3 Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title " Getting the Blockchain " \
    --menu "You need a copy of the Bitcoin Blockchain - choose method:" 13 75 5 \
    C "COPY    --> Copy from laptop/node over LAN (±6hours)" \
    S "SYNC    --> Selfvalidate all Blocks (VERY SLOW ±2month)" 2>&1 >/dev/tty)

  # Bitcoin on stronger RaspberryPi4 (new DEFAULT)
  elif [ ${network} = "bitcoin" ]; then
    echo "Bitcoin-RP4 Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title " Getting the Blockchain " \
    --menu "You need a copy of the Bitcoin Blockchain - choose method:" 13 75 5 \
    S "SYNC    --> Selfvalidate all Blocks (DEFAULT ±2days)" \
    C "COPY    --> Copy from laptop/node over LAN (±6hours)" 2>&1 >/dev/tty)

  # Litecoin
  elif [ ${network} = "litecoin" ]; then
    echo "Litecoin Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title " Getting the Blockchain " \
    --menu "You need a copy of the Litecoin Blockchain:" 13 75 4 \
    S "SYNC    --> Selfvalidate all Blocks (±1day)" 2>&1 >/dev/tty)

  # error
  else
    echo "FAIL Unknown network(${network})"
    exit 1
   fi

  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=50/g" ${infoFile}

  clear
  case $menuitem in
          C)
              /home/admin/50copyHDD.sh
              ;;      
          S)
              /home/admin/50syncHDD.sh
              /home/admin/10setupBlitz.sh
              ;;
          *)
              echo "Use 'raspiblitz' command to return to setup ..."
              ;;
  esac
  exit 1

fi # end HDD is already auto-mounted


# --- the HDD is not auto-mounted --> very early stage of setup

# if the script is called for the first time
if [ ${setupStep} -eq 0 ]; then
  # run initial user dialog
  /home/admin/20setupDialog.sh
fi

# if the script is called for the first time
if [ ${setupStep} -eq 20 ]; then
  # run initial user dialog
  /home/admin/30initHDD.sh
  exit 1
fi

# the HDD is already ext4 formatted and contains blockchain data
if [ "${hddFormat}" = "ext4" ] || [ "${hddFormat}" = "btrfs" ]; then
  if [ ${hddGotBlockchain} -eq 1 ]; then
    echo "HDD was already initialized/prepared"
    echo "Now needs to be mounted"
    /home/admin/40addHDD.sh
    exit 1
  fi
fi

# the HDD had no init yet
echo "init HDD ..."
/home/admin/30initHDD.sh
exit 1