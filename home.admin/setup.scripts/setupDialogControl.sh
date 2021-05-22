#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"

# remember original setupphase
orgSetupPhase="${setupPhase}"

# init SETUPFILE & temp dir on mem drive
sudo mkdir /var/cache/raspiblitz/temp
sudo chown admin:admin /var/cache/raspiblitz/temp
sudo rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP STATE" > $SETUPFILE
sudo chown admin:admin $SETUPFILE
sudo chmod 777 $SETUPFILE

############################################
# QuickOption: Update
if [ "${setupPhase}" == "update" ]; then
  # show update dialog
  /home/admin/setup.scripts/dialogUpdate.sh
  if [ "$?" == "0" ]; then
    # proceed with provision (mark Password A to be set)
    echo "# OK update process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    setupPhase="setup"
    echo "# you refused recovery option - defaulting to normal setup"
  fi
fi

############################################
# QuickOption: Recovery
if [ "${setupPhase}" == "recovery" ]; then
  # show recovery dialog
  /home/admin/setup.scripts/dialogRecovery.sh
  if [ "$?" == "0" ]; then
    # proceed with provision (mark Password A to be set)
    echo "# OK recover process starting .."
    echo "setPasswordA=1" >> $SETUPFILE
  else
    # default to normal setup options
    setupPhase="setup"
    echo "# you refused recovery option - defaulting to normal setup"
  fi
fi

############################################
# QuickOption: Migration from other node
if [ "${setupPhase}" == "migration" ]; then
  # show recovery dialog
  echo "# Starting migration dialog ..."
  /home/admin/setup.scripts/dialogMigration.sh ${migrationOS}
  if [ "$?" == "0" ]; then
    # mark migration to happen on provision
    echo "migrationOS='umbrel'" >> $SETUPFILE
    echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE
    # user needs to reset password A, B & C
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  else
    # on cancel - default to normal setup
    setupPhase="setup"
    echo "# you refused node migration option - defaulting to normal setup"
    exit 1
  fi

fi

############################################
# DEFAULT: Basic Setup menu
# user might default to from quick options
if [ "${setupPhase}" == "setup" ]; then

  echo "# Starting basic setup dialog ..."
  /home/admin/setup.scripts/dialogBasicSetup.sh
  menuresult=$?

  # exit to terminal
  if [ "${menuresult}" == "3" ]; then
    exit 1
  fi

  # shutdown without changes
  if [ "${menuresult}" == "2" ]; then
    sudo shutdown now
    exit 0
  fi

  ###############################################
  # FORMAT DRIVE on NEW SETUP or MIGRATION UPLOAD 
  if [ "${menuresult}" == "0" ] || [ "${menuresult}" == "1" ]; then

    # check if there is a blockchain to use (so HDD is already formatted)
    # thats also true if the node is coming from another nodeOS
    existingBlockchain=""
    if [ "${hddBlocksLitecoin}" == "1" ]; then
      existingBlockchain="LITECOIN"
    fi
    if [ "${hddBlocksBitcoin}" == "1" ] || [ "${hddGotMigrationData}" != "" ]; then
      existingBlockchain="BITCOIN"
    fi

    # ask user about possible existing blockchain and formatting HDD
    /home/admin/setup.scripts/dialogDeleteData.sh "${existingBlockchain}"
    userChoice=$?
    if [ "${userChoice}" == "1" ]; then

      # FORMAT DATA DRIVE
      echo "TODO: Format HDD/SSD"

      # DEBUG EXIT
      exit 1
    
    elif [ "${userChoice}" == "2" ]; then

      # KEEP BLOCKCHAIN + DLETE ALL THE REST
      
      # when blockchain comes from another node migrate data first
      if [ "${hddGotMigrationData}" != "" ]; then
        echo "TODO: Migrate data from '{hddGotMigrationData}'"
      fi

      # delete everything but blockchain
      echo "TODO: Delete everything but blockchain"

      # by keeping that blockchain - user choosed already the blockchain type
      if [ "${hddBlocksLitecoin}" == "1" ]; then
        echo "network=litecoin" >> $SETUPFILE
      else
        echo "network=bitcoin" >> $SETUPFILE
      fi

      # DEBUG EXIT
      exit 1

    else

      # STOP SETUP  - loop back to setup menu start
      exit 0

    fi

  fi

  ############################################
  # UPLOAD MIGRATION
  if [ "${menuresult}" == "1" ]; then
    /home/admin/setup.scripts/dialogMigration.sh raspiblitz
    if [ "$?" == "1" ]; then
      # upload did not worked .. exit with 0 to restart process from outside loop
      echo "Upload failed ... return to menu"
      sleep 2
      exit 0
    fi
    # user needs to reset password A
    echo "setPasswordA=1" >> $SETUPFILE
  fi

  ############################################
  # FRESH SETUP
  if [ "${menuresult}" == "0" ]; then

    ############################################
    # Choosing Blockchain & Lightning

    echo "# Starting Blockchain & Lightning selection ..."
    /home/admin/setup.scripts/dialogBlockchainLightning.sh
    if [ "$?" == "1" ]; then
      # exit with 0 to restart process from outside loop
      exit 0
    fi

    ############################################
    # Setting Name for Node

    echo "# Starting name dialog ..."
    /home/admin/setup.scripts/dialogName.sh

    ############################################
    # Lightning Wallet (new or restore) do this before passwords
    # because password C not needed if LND rescue file is uploaded

    lightningWalletDone=0
    while [ "${lightningWalletDone}" == "0" ]
    do

      echo "# Starting lightning wallet dialog ..."
      /home/admin/setup.scripts/dialogLightningWallet.sh

      # only if dialog exited clean end loop
      if [ "$?" == "0" ]; then
        lightningWalletDone=1
      fi

      # allow user to cancel to terminal on dialog main menu
      # all other cancels have other exit codes
      if [ "$?" == "1" ]; then
        echo "# you selected cancel - sending exit code 1"
        exit 1
      fi

    done

    echo "# CREATING raspiblitz.conf from your setup choices"

    # source the raspiblitz version
    source /home/admin/_version.info

    # source the setup state fresh
    source $SETUPFILE

    # prepare config file
    CONFIGFILE="/mnt/hdd/raspiblitz.conf"
    sudo rm $CONFIGFILE 2>/dev/null
    sudo chown admin:admin $CONFIGFILE
    sudo chmod 777 $CONFIGFILE

    # write basic config file data
    echo "# RASPIBLITZ CONFIG FILE" > $CONFIGFILE
    echo "raspiBlitzVersion='${codeVersion}'" >> $CONFIGFILE
    echo "lcdrotate=1" >> $CONFIGFILE
    echo "lightning=${lightning}" >> $CONFIGFILE
    echo "network=${network}" >> $CONFIGFILE
    echo "chain=main" >> $CONFIGFILE
    echo "runBehindTor=on" >> $CONFIGFILE
  
    # user needs to set all passwords
    echo "setPasswordA=1" >> $SETUPFILE
    echo "setPasswordB=1" >> $SETUPFILE
    echo "setPasswordC=1" >> $SETUPFILE
  fi

fi

############################################
# Enter Passwords
# for fresh setup & migration

echo "# Starting passwords dialog ..."
/home/admin/setup.scripts/dialogPasswords.sh

# set flag for bootstrap process to kick-off provision process
sudo sed -i "s/^state=.*/state=waitprovision/g" /home/admin/raspiblitz.info
  
clear
echo "# setup dialog done - results in:"
echo "# $SETUPFILE"
echo "# $CONFIGFILE"