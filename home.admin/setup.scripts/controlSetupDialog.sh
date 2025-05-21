#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info
# get values from cache

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"

# init SETUPFILE & temp dir on mem drive
sudo mkdir /var/cache/raspiblitz/temp
sudo chown admin:admin /var/cache/raspiblitz/temp
sudo rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP STATE" > $SETUPFILE
sudo chown admin:admin $SETUPFILE
sudo chmod 777 $SETUPFILE

source <(/home/admin/_cache.sh get dnsworking)

# remember original setupphase
orgSetupPhase="${setupPhase}"
menuresult=""
askBootFromNVMe="0"

############################################
# PRESETUP: SET DNS (just if needed)
if [ "${dnsworking}" == "0" ]; then
  sudo /home/admin/config.scripts/internet.dns.sh test
fi

############################################
# QuickOption: Update
if [ "${setupPhase}" == "update" ]; then
  # show update dialog
  /home/admin/setup.scripts/dialogUpdate.sh
  if [ "$?" = "0" ]; then
    # proceed with provision (mark Password A to be set)
    menuresult="4"
    echo "# OK update process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused recovery option - defaulting to normal setup menu"
  fi
fi

############################################
# QuickOption: Recovery
if [ "${setupPhase}" == "recovery" ]; then
  # show recovery dialog
  /home/admin/setup.scripts/dialogRecovery.sh
  if [ "$?" = "0" ]; then
    # proceed with provision (mark Password A to be set)
    echo "# OK recover process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused recovery option - defaulting to normal setup menu"
  fi
fi

############################################
# QuickOption: Recovery
if [ "${setupPhase}" == "biggerdevice" ]; then
  # show recovery dialog
  /home/admin/setup.scripts/dialogBiggerDevice.sh
  /home/admin/_cache.sh set setupPhase "setup"
  setupPhase="setup"
fi

############################################
# QuickOption: Migration from other node
if [ "${setupPhase}" == "migration" ]; then

  source <(/home/admin/_cache.sh get system_setup_storageMigration)
  
  # show recovery dialog
  echo "# Starting migration dialog (${system_setup_storageMigration}) ..."

  /home/admin/setup.scripts/dialogMigration.sh ${system_setup_storageMigration} "normal"
  if [ "$?" = "0" ]; then
    # mark migration to happen on provision
    echo "migrationOS='${system_setup_storageMigration}'" >> $SETUPFILE
    # user needs to reset password A, B & C
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  else
    # on cancel - default to normal setup
    /home/admin/_cache.sh set setupPhase "setup"
    echo "# you refused node migration option - defaulting to normal setup"
    /home/admin/00raspiblitz.sh
    exit 1
  fi

fi

############################################
# Fix: BOOT ORDER CHANGE FAILED
source <(/home/admin/_cache.sh get system_setup_secondtry)
if [ "${system_setup_secondtry}" == "1" ]; then
  whiptail --title " BOOT ORDER CHANGE FAILED? " --msgbox "
You already ran a setup/recover and copied the system to SSD/NVMe. But it booted again from the old install medium. To fix it:

Press OK
Wait until shutdown.
Remove install medium.
Power up again." 16 50
  sudo shutdown now
  exit 1
fi

# fresh import setup values
source /home/admin/raspiblitz.info

############################################
# DEFAULT: Basic Setup menu
# user might default to from quick options
if [ "${setupPhase}" = "setup" ]; then

  echo "# Starting basic setup dialog ..."
  /home/admin/setup.scripts/dialogBasicSetup.sh ${orgSetupPhase}
  menuresult=$?

  # explicit setup
  if [ "${menuresult}" = "0" ]; then
    echo "menuchoice='setup'" >> $SETUPFILE
  fi

  # upload migration file
  if [ "${menuresult}" = "1" ]; then
    echo "menuchoice='filemigration'" >> $SETUPFILE
    echo "setPasswordA=1" >> $SETUPFILE
  fi

  # shutdown without changes
  if [ "${menuresult}" = "2" ]; then
    sudo shutdown now
    exit 0
  fi

  # exit to terminal
  if [ "${menuresult}" = "3" ]; then
    /home/admin/_cache.sh set setupPhase "${orgSetupPhase}"
    exit 1
  fi

  # menu RECOVER menu option
  if [ "${menuresult}" = "4" ]; then
    setupPhase="${orgSetupPhase}"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
    # proceed with provision (mark Password A to be set)
    echo "# OK update process starting .."
    echo "menuchoice='recover'" >> $SETUPFILE
    echo "setPasswordA=1" >> $SETUPFILE
  fi
  
  # menu MIGRATE menu option
  if [ "${menuresult}" = "5" ]; then
    setupPhase="${orgSetupPhase}"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
    echo "menuchoice='uploadmigrate'" >> $SETUPFILE
    # mark migration to happen on provision
    echo "migrationOS='${hddGotMigrationData}'" >> $SETUPFILE
    # user needs to reset password A, B & C
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  fi

  # migrate HDD
  if [ "${menuresult}" = "6" ]; then
    
    # ask user details on migrate HDD (resutls in cache)
    sudo /home/admin/config.scripts/blitz.data.sh migration hdd menu-prepare
    if [ "$?" == "1" ]; then
      # user wants to exit
      exit 0
    fi
    echo "setPasswordA=1" >> $SETUPFILE
    echo "menuchoice='hddmigrate'" >> $SETUPFILE
    source <(/home/admin/_cache.sh get hddMigrateDeviceFrom)
    echo "hddMigrateDeviceFrom='${hddMigrateDeviceFrom}'" >> $SETUPFILE
    source <(/home/admin/_cache.sh get hddMigrateDeviceTo)
    echo "hddMigrateDeviceTo='${hddMigrateDeviceTo}'" >> $SETUPFILE
  fi

  ###################################################
  # FORMAT DRIVE on NEW SETUP or MIGRATION UPLOAD/HDD 
  if [ "${menuresult}" = "0" ] || [ "${menuresult}" = "1" ]  || [ "${menuresult}" = "6" ]; then

    source <(/home/admin/_cache.sh get system_setup_storageMigration system_setup_storageBlockchainGB system_setup_bootFromStorage system_setup_cleanDrives system_setup_storagePartitionsCount)

    # handle existing blockchain data # CLOSED FOR REPAIR #5029
    existingBlockchain=""
    #if [ "${system_setup_storageBlockchainGB}" != "" ] && [ "${system_setup_storageBlockchainGB}" != "0" ]; then
      # allow, when not bootFromStorage
      #if [ "${system_setup_bootFromStorage}" == "0" ]; then
      #  echo "# Existing blockchain can be used - cannot be moved to new drive layout"
      #  existingBlockchain="BITCOIN"
      # allow, when bootFromStorage & storage already has 3 partitions (new drive layout)
      #elif [ "${system_setup_bootFromStorage}" == "1" ] && [ "${system_setup_storagePartitionsCount}" == "3" ] ; then
      #  echo "# Existing blockchain can be used - already new drive layout"
      #  existingBlockchain="BITCOIN"
      # otherwise - dont use existing blockchain
    #  else
    #    echo "# Existing blockchain will not be used - to allow transfere to new drive layout"
    #  fi
    #fi

    # ask user about possible existing blockchain and formatting HDD
    if [ "${menuresult}" != "6" ]; then
      if [ "${system_setup_cleanDrives}" == "1" ]; then
        # no need to ask user there is no data on drives - just delete all data
        echo "deleteData='all'" >> $SETUPFILE
      else
        /home/admin/setup.scripts/dialogDeleteData.sh "${existingBlockchain}"
        userChoice=$?
        if [ "${userChoice}" = "1" ]; then
          echo "deleteData='all'" >> $SETUPFILE
        elif [ "${userChoice}" = "2" ]; then
          echo "deleteData='keepBlockchain'" >> $SETUPFILE
        else
          # STOP SETUP  - loop back to setup menu start
          exit 0
        fi
      fi
    fi  

  fi

  ############################################
  # UPLOAD MIGRATION
  if [ "${menuresult}" == "1" ]; then
    echo "uploadMigration=1" >> $SETUPFILE
    echo "setPasswordA=1" >> $SETUPFILE
  fi

  ############################################
  # HDD MIGRATION
  if [ "${menuresult}" == "6" ]; then
    echo "hddMigration=1" >> $SETUPFILE
    echo "setPasswordA=1" >> $SETUPFILE
    echo "deleteData='all'" >> $SETUPFILE
  fi

  ############################################
  # FRESH SETUP
  if [ "${menuresult}" == "0" ]; then

    # user needs to set all passwords (defaults)
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE

    ############################################
    # Setting Name for Node

    echo "# Starting name dialog ..."
    /home/admin/setup.scripts/dialogName.sh

    ############################################
    # Choosing Blockchain & Lightning

    echo "# Starting Blockchain & Lightning selection ..."
    /home/admin/setup.scripts/dialogBlockchainLightning.sh
    if [ "$?" == "1" ]; then
      # exit with 0 to restart process from outside loop
      exit 0
    fi

    ############################################
    # Lightning Wallet (new or restore) do this before passwords
    # because password C not needed if LND rescue file is uploaded

    lightningWalletDone=0
    source ${SETUPFILE}
    if [ "${lightning}" = "none" ]; then
      lightningWalletDone=1
      # also disable asking for password c if no lightning implementation was chosen
      sed -i "s/^setPasswordC=.*/setPasswordC=0/g" ${SETUPFILE}
    fi 
    while [ "${lightningWalletDone}" == "0" ]
    do

      if [ "${lightning}" = "lnd" ]; then

        echo "# Starting lightning wallet dialog for LND ..."
        /home/admin/setup.scripts/dialogLightningWallet-lnd.sh
        dialogResult=$?

      elif [ "${lightning}" = "cl" ]; then

        echo "# Starting lightning wallet dialog for CORE LIGHTNING ..."
        /home/admin/setup.scripts/dialogLightningWallet-cl.sh
        dialogResult=$?

      else
        echo "FAIL: unknown lightning implementation (${lightning})"
        lightningWalletDone=1
        sleep 8
      fi

      # break loop only if a clean exit
      if [ "${dialogResult}" = "0" ]; then
        lightningWalletDone=1
      fi

      # allow user to cancel to terminal on dialog main menu
      # all other cancels have other exit codes
      if [ "${dialogResult}" = "1" ]; then
        echo "# you selected cancel - sending exit code 1"
        exit 1
      fi

    done

  fi

fi

############################################
# Enter Passwords
# for fresh setup & migration

echo "# Starting passwords dialog ..."
sudo /home/admin/setup.scripts/dialogPasswords.sh || exit 1

# check if password A is set
source ${SETUPFILE}
if [ "${passwordA}" = "" ]; then
  sudo /home/admin/config.scripts/blitz.error.sh $(basename "$0") "missing-passworda-1" "missing passwordA(1) in (${SETUPFILE}) after dialogPasswords.sh" ""
  exit 1
fi

############################################
# Ask System Copy
source <(/home/admin/_cache.sh get system_setup_askSystemCopy)
if [ "${system_setup_askSystemCopy}" = "1" ]; then
  # ask user about system copy
  /home/admin/setup.scripts/dialogSystemCopy.sh
  userChoice=$?
  if [ "${userChoice}" == "0" ]; then
    echo "systemCopy=1" >> $SETUPFILE
  else
    echo "systemCopy=0" >> $SETUPFILE
  fi
fi

# set flag for bootstrap process to kick-off provision process
/home/admin/_cache.sh set state "waitprovision"
clear