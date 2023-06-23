#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# ---------------------------------------------------"
 echo "# LND RESCUE FILE (tar.gz of complete lnd directory)"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh lnd-export"
 echo "# lnd.backup.sh lnd-export-gui"
 echo "# lnd.backup.sh lnd-import [file]"
 echo "# lnd.backup.sh lnd-import-gui [setup|production] [?resultfile]"
 echo "# ---------------------------------------------------"
 echo "# STATIC CHANNEL BACKUP"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh scb-export"
 echo "# lnd.backup.sh scb-export-gui"
 echo "# lnd.backup.sh scb-import [file]"
 echo "# lnd.backup.sh scb-import-gui [setup|production] [?resultfile]"
 echo "# ---------------------------------------------------"
 echo "# SEED WORDS"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh seed-export-gui [lndseeddata]"
 echo "# lnd.backup.sh seed-import-gui [resultfile]"
 echo "# ---------------------------------------------------"
 echo "# RECOVERY"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh [mainnet|signet|testnet] recoverymode [on|off|status]"
 exit 1
fi

# 1st PARAMETER [mainnet|signet|testnet]
if [ "$1" == "mainnet" ] || [ "$1" == "testnet" ] || [ "$1" == "signet" ]; then

  # prepare all chain dependent variables
  lndChain="$1"
  mode="$2"
  netprefix=""
  if [ "${lndChain}" == "testnet" ]; then
    netprefix="t"
  fi
  if [ "${lndChain}" == "signet" ]; then
    netprefix="s"
  fi

  ################################
  # RECOVERY
  ################################

  # LND is considered in "recoverymode" when it gets started with --reset-wallet-transactions parameter
  # so it will forgets all the old on-chain transactions. This will trigger wallet unlock with
  # recovery window to rescan for transactions and background process will monitor when finished

  if [ ${mode} = "recoverymode" ]; then

    # check if started with sudo
    if [ "$EUID" -ne 0 ]; then 
      echo "error='run as root'"
      exit 1
    fi

        # status
    recoverymodeStatus=$(cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep -c "^reset-wallet-transactions=true")
    if [ "$3" == "status" ]; then
      if [ ${recoverymodeStatus} -gt 0 ]; then
        echo "recoverymode=1"
      else
        echo "recoverymode=0"
      fi
      exit 0
    fi

    # on
    if [ "$3" == "on" ]; then
      if [ ${recoverymodeStatus} -gt 0 ]; then
        echo "# recoverymode already on"
        exit 0
      fi

      # make sure config entry exits
      entryExists=$(cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep -c "^reset-wallet-transactions=")
      if [ $entryExists -eq 0 ]; then
        # find section
        sectionLine=$(cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep -n "^\[Application Options\]" | cut -d ":" -f1)
        insertLine=$(expr $sectionLine + 1)
        sed -i "${insertLine}ireset-wallet-transactions=false" /mnt/hdd/lnd/${netprefix}lnd.conf
      fi

      # activate reset-wallet-transactions in lnd.conf
      echo "# activating recovery mode ..."
      sed -i 's/^reset-wallet-transactions=.*/reset-wallet-transactions=true/g' /mnt/hdd/lnd/${netprefix}lnd.conf
      echo "# OK - restart/reboot needed for: ${netprefix}lnd.service"

      # set system status
      /home/admin/config.scripts/blitz.conf.sh set ln_lnd_${lndChain}_sync_initial_done 0 /home/admin/raspiblitz.info
      source <(/home/admin/_cache.sh get chain lightning)
      if [ "${lndChain}" == "${chain}net" ] && [ "${lightning}" == "lnd" ]; then
        /home/admin/_cache.sh set ln_default_sync_initial_done 0
      fi
    
      exit 0
    fi

    # off
    if [ "$3" == "off" ]; then
      if [ ${recoverymodeStatus} -eq 0 ]; then
        echo "# recoverymode already off"
        exit 0
      fi

      # remove --reset-wallet-transactions parameter in systemd service
      echo "# deactivating recovery mode ..."
      sed -i 's/^reset-wallet-transactions=.*/reset-wallet-transactions=false/g' /mnt/hdd/lnd/${netprefix}lnd.conf
      

      echo "# OK - restart/reboot needed for: ${netprefix}lnd.service"
      exit 0
    fi

    # parameter fallback
    echo "error='unknown parameter'"
    exit 1

  fi

fi

# 1st PARAMETER all other: action
mode="$1"

################################
# LND RESCUE FILE - EXPORT
################################

if [ ${mode} = "lnd-export" ]; then

  echo "# *** LND.RESCUE --> BACKUP"
  downloadPath="/home/admin"
  fileowner="admin"

  # add lnd version info into lnd dir (to detect needed updates later)
  lndVersion=$(sudo -u bitcoin lncli getinfo 2>/dev/null | jq -r ".version" | cut -d ' ' -f1)
  sudo rm /mnt/hdd/lnd/version.info 2>/dev/null
  echo "${lndVersion}" > /home/admin/lnd.version.info
  sudo mv /home/admin/lnd.version.info /mnt/hdd/lnd/version.info
  sudo chown bitcoin:bitcoin /mnt/hdd/lnd/version.info

  # stop LND
  echo "# Stopping lnd..."
  sudo systemctl stop lnd 2>/dev/null
  sleep 5
  echo "# OK"
  echo 

  # tar it
  timestamp=$(date +%Y%m%d%H%M)
  filename="${downloadPath}/lnd-rescue-${timestamp}"
  fileext=".tar.gz"
  sudo tar -zcvf ${filename}${fileext} /mnt/hdd/lnd 1>&2
  sudo chown ${fileowner}:${fileowner} ${filename}${fileext} 1>&2

  # delete old backups
  # rm ${downloadPath}/lnd-rescue-*.tar.gz 2>/dev/null 1>/dev/null

  # name with md5 checksum and timestamp
  md5checksum=$(md5sum ${filename}${fileext} | head -n1 | cut -d " " -f1)
  mv ${filename}${fileext} ${filename}-${md5checksum}${fileext} 1>&2
  filename=${filename}-${md5checksum}${fileext} 1>&2
  byteSize=$(ls -l ${filename} | awk '{print $5}')

  # check file size
  if [ ${byteSize} -lt 100 ]; then
    echo "error='backup is empty'"
    exit 1
  fi

  # copy backup over
  source <(/home/admin/config.scripts/blitz.backupdevice.sh status)
  if [ $isMounted == 1 ]; then
     sudo cp ${filename} /mnt/backup
     echo "copied to backup device"
  fi

  # output result data
  echo "# lnd service is stopped for security"
  echo "filename='${downloadPath}/lnd-rescue-${md5checksum}.tar.gz'"
  echo "fileowner='${fileowner}'"
  echo "size=${byteSize}"
  exit 0
fi

if [ ${mode} = "lnd-export-gui" ]; then

  # create lnd rescue file
  echo "# lnd.backup lnd-export-gui ..." 
  source <(/home/admin/config.scripts/lnd.backup.sh lnd-export)
  if [ "${error}" != "" ]; then
    echo "error='${error}'"
    exit 1
  fi

  # get local ip info
  source <(/home/admin/config.scripts/internet.sh status local)

  # offer SFTP for download
  clear
  echo
  echo "********************************"
  echo "* DOWNLOAD THE LND RESCUE FILE *"
  echo "********************************"
  echo 
  echo "ON YOUR MAC & LINUX LAPTOP - RUN IN NEW TERMINAL:"
  echo "scp '${fileowner}@${localip}:${filename}' ./"
  echo "ON WINDOWS - RUN IN CMD:"
  echo "scp ${fileowner}@${localip}:${filename} ."
  echo "Use password A to authenticate file transfer."
  echo
  echo "Check for correct file size after transfer: ${size} byte"
  echo "Use command: stat lnd-rescue-*.tar.gz"
  echo
  echo "BEWARE: Your Lightning node is now stopped. It's safe to backup the data and"
  echo "restore it on a fresh RaspiBlitz. But once this Lightning node gets started"
  echo "again or rebooted, it's not advised to restore the backup file because"
  echo "it would contain outdated channel data and can lead to loss of channel funds."
  exit 0
fi

################################
# LND RESCUE FILE - IMPORT
################################

if [ ${mode} = "lnd-import" ]; then

  # 2nd PARAMETER: file to import (expect that the file was valid checked from calling script)
  filename=$2
  if [ "${filename}" == "" ]; then
    echo "error='filename missing'"
    exit 1
  fi
  fileExists=$(sudo ls ${filename} 2>/dev/null | grep -c "${filename}")
  if [ "${fileExists}" != "1" ]; then
    echo "error='filename not found'"
    exit 1
  fi

  # stop LND
  echo "# stopping lnd..."
  sudo systemctl stop lnd 1>/dev/null
  sleep 5

  # clean DIR
  echo "# cleaning old LND data ..."
  sudo rm -r /mnt/hdd/lnd/* 1>/dev/null 2>/dev/null

  # unpack zip
  echo "# restoring LND data from ${filename} ..."
  sudo tar -xf ${filename} -C / 1>/dev/null
  sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd 1>/dev/null

  # lnd version of LND rescue file (thats packed as extra info in the file)
  # its included since RaspiBlitz v1.7.1 /mnt/hdd/lnd/version.info
  # this can happen if someone uses the manual LND update and then uploads to an old default LND 
  # if so just signal this in the output (but also this file might be empty, when LND was dead)
  
  echo "# DONE - lnd service is still stopped - start manually with command:"
  echo "# sudo systemctl start lnd"
  exit 0

fi

if [ ${mode} = "lnd-import-gui" ]; then

  # get by second parameter if this call if happening during setup or production
  scenario=$2
  if [ "${scenario}" != "setup" ] && [ "${scenario}" != "production" ]; then
    echo "error='missing parameter'"
    exit 1
  fi

  # scenario setup needs a 3rd parameter - the RESULTFILE to store results in
  if [ "${scenario}" == "setup" ]; then
    RESULTFILE=$3
    if [ "${RESULTFILE}" == "" ]; then
      echo "error='missing parameter'"
      exit 1 
    fi
  fi

  # determine password info based on scenario
  if [ "${scenario}" == "setup" ]; then
    passwordInfo="password 'raspiblitz'"
  else
    passwordInfo="your Password A"
  fi

  # get defaultUploadPath, localIP, etc
  source <(sudo /home/admin/config.scripts/blitz.upload.sh prepare-upload)

  filename=""
  while [ "${filename}" == "" ]
    do
      clear 
      echo "******************************"
      echo "* UPLOAD THE LND RESCUE FILE *"
      echo "******************************"
      echo "If you have a lnd-rescue backup file on your laptop you can now"
      echo "upload it and restore your latest LND state."
      echo
      echo "CAUTION: Dont restore old LND states - risk of loosing funds!"
      echo
      echo "To make upload open a new terminal on your laptop,"
      echo "change into the directory where your lnd-rescue file is and"
      echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
      echo "scp -r ./lnd-rescue-*.tar.gz ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
      echo
      echo "Use ${passwordInfo} to authenticate file transfer."
      echo "PRESS ENTER when upload is done"
      read key

      # check upload (will return filename or error)
      source <(sudo /home/admin/config.scripts/blitz.upload.sh check-upload lnd-rescue)
      if [ "${filename}" != "" ]; then
        echo "OK - File found: ${filename}"
        echo "PRESS ENTER to continue."
        read key
      elif [ "${error}" == "not-found" ]; then
        echo "# WARNING #"
        echo "There was no upload found in ${defaultUploadPath}"
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "multiple" ]; then
        echo "# WARNING #"
        echo "There are multiple lnd-rescue files in directory ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "invalid" ]; then
        echo "# WARNING #"
        echo "The file uploaded is not a valid (complete upload failed or not correct file)."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      else
        # create no result file and exit
        echo "# WARNING # Unknown State (report to devs)"
        exit 1
      fi

      if [ "${keyRetry}" == "x" ] || [ "${keyRetry}" == "X" ] || [ "${keyRetry}" == "'x'" ]; then
        # create no result file and exit
        echo "# USER CANCEL"
        exit 1
      fi

  done

  # in setup scenario the final import is happening during provison
  if [ "${scenario}" == "setup" ]; then
    # just add lndrescue filename to give file
    echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
    echo "lndrescue='${filename}'" >> $RESULTFILE
    exit 0
  fi

  # in production now start restoring LND data based on file
  source /mnt/hdd/raspiblitz.conf
  
  # ask security question before deleting old wallet
  echo "WARNING: This will delete/overwrite the LND state/funds of this RaspiBlitz."
  echo
  echo "Write the word 'override' and press ENTER to CONTINUE:"
  read securityInput
  if [ "${securityInput}" != "override" ] && [ "${securityInput}" != "'override'" ]; then
      echo
      echo "CANCELED import of uploaded rescue file"
      exit 1
  fi
  echo

  # run import process
  echo "OK deleting old LND data & restoring imported rescue file ..."
  source <(sudo /home/admin/config.scripts/lnd.backup.sh lnd-import ${filename})

  # TODO: check if update of LND is needed (see detailes in lnd-import) for edge case

  # turn off auto-unlock if activated because password c might now change
  if [ "${autoUnlock}" == "on" ]; then
    /home/admin/config.scripts/lnd.autounlock.sh off
  fi
  
  # restarting lnd & give final info
  sudo systemctl start lnd
  echo "DONE - lnd is now restarting .. Password C is now like within your rescue file"
  echo "Check that LND is starting up correctly and your old channel & funds are restored."
  echo "Take into account that some channels might have been force closed in the meanwhile."
  exit 0
fi

####################################
# STATIC CHANEL BACKUP FILE - EXPORT
####################################

if [ ${mode} = "scb-export" ]; then

  # get file info
  source /mnt/hdd/raspiblitz.conf
  echo "filename='/mnt/hdd/lnd/data/chain/${network}/${chain}net/channel.backup'"
  echo "fileuser='bitcoin'"

  # localip
  source <(/home/admin/config.scripts/internet.sh status local)
  echo "localip='${localip}'"

  exit 0
fi

if [ ${mode} = "scb-export-gui" ]; then

  # get the scb info
  source <(sudo /home/admin/config.scripts/lnd.backup.sh scb-export)

  # show download info
  clear
  echo "**************************************"
  echo "* DOWNLOAD STATIC CHANEL BACKUP FILE *"
  echo "**************************************"
  echo 
  echo "RUN THE FOLLOWING COMMAND ON YOUR LAPTOP IN NEW TERMINAL:"
  echo "scp -r ${fileuser}@${localip}:${filename} ./"
  echo ""
  echo "Use password A to authenticate file transfer."
  echo
  echo "NOTE: Use this file when setting up a fresh RaspiBlitz by choosing" 
  echo "option OLD WALLET and then SCB+SEED -> Seed & channel.backup file" 
  echo "Will just recover on-chain & channel-funds, but closing all channels" 
  exit 0
fi

####################################
# STATIC CHANEL BACKUP FILE - IMPORT
####################################

if [ ${mode} = "scb-import" ]; then

  # 2nd PARAMETER: file to import (expect that the file was valid checked from calling script)
  filename=$2
  if [ "${filename}" == "" ]; then
    echo "error='filename missing'"
    exit 1
  fi
  fileExists=$(sudo ls ${filename} 2>/dev/null | grep -c "${filename}")
  if [ "${fileExists}" != "1" ]; then
    echo "error='filename not found'"
    exit 1
  fi

  # place the the file at '/home/admin/channel.backup'
  sudo mv ${filename} /home/admin/channel.backup
  sudo chmod 777 /home/admin/channel.backup
  sudo chown admin:admin /home/admin/channel.backup
  echo "# OK - placed SCB file at /home/admin/channel.backup"

fi

if [ ${mode} = "scb-import-gui" ]; then

  # get by second parameter if this call if happening during setup or production
  scenario=$2
  if [ "${scenario}" != "setup" ] && [ "${scenario}" != "production" ]; then
    echo "error='missing parameter'"
    exit 1
  fi

  # scenario setup needs a 3rd parameter - the RESULTFILE to store results in
  if [ "${scenario}" == "setup" ]; then
    RESULTFILE=$3
    if [ "${RESULTFILE}" == "" ]; then
      echo "error='missing parameter'"
      exit 1 
    fi
  fi

  # determine password info based on scenario
  if [ "${scenario}" == "setup" ]; then
    passwordInfo="password 'raspiblitz'"
  else
    passwordInfo="your Password A"
  fi

  # get defaultUploadPath, localIP, etc
  source <(sudo /home/admin/config.scripts/blitz.upload.sh prepare-upload)

  filename=""
  while [ "${filename}" == "" ]
    do
    
      clear
      echo "**********************************"
      echo "* UPLOAD THE channel.backup FILE *"
      echo "**********************************"
      echo
      echo "If you have the channel.backup file on your laptop or on"
      echo "another server you can now upload it to the RaspiBlitz."
      echo
      echo "To make upload open a new terminal and change,"
      echo "into the directory where your lnd-rescue file is and"
      echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
      echo "scp ./channel.backup ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
      echo ""
      echo "Use ${passwordInfo} to authenticate file transfer."
      echo "PRESS ENTER when upload is done."
      read key

      # check upload (will return filename or error)
      source <(sudo /home/admin/config.scripts/blitz.upload.sh check-upload scb)
      if [ "${filename}" != "" ]; then
        echo "OK - File found: ${filename}"
        echo "PRESS ENTER to continue."
        read key
      elif [ "${error}" == "not-found" ]; then
        echo "# WARNING #"
        echo "There was no upload found in ${defaultUploadPath}"
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "multiple" ]; then
        echo "# WARNING #"
        echo "There are multiple lnd-rescue files in directory ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "invalid" ]; then
        echo "# WARNING #"
        echo "The file uploaded is not a valid (complete upload failed or not correct file)."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      else
        echo "# WARNING # Unknown State (report to devs)"
        exit 1
      fi

      if [ "${keyRetry}" == "x" ] || [ "${keyRetry}" == "X" ] || [ "${keyRetry}" == "'x'" ]; then
        # create no result file and exit
        echo "# USER CANCEL"
        exit 1
      fi

  done

  # in setup scenario the final import is happening during provison
  if [ "${scenario}" == "setup" ]; then
    echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
    echo "staticchannelbackup='${filename}'" >> $RESULTFILE
  fi

  # run import process
  source <(sudo /home/admin/config.scripts/lnd.backup.sh scb-import "${filename}")
  echo "# DONE - placed SCB file at /home/admin/channel.backup"
  exit 0
fi

####################################
# SEED WORDS - GUI PARTS
####################################

if [ ${mode} = "seed-export-gui" ]; then

  # use text snippet for testing:
  # 

  # 2nd PARAMETER: lnd seed data
  seedwords6x4=$2
  if [ "${seedwords6x4}" == "" ]; then
    echo "error='missing parameter'"
    exit 1 
  fi

  ack=0
  while [ ${ack} -eq 0 ]
  do
    whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "LND Wallet got created. Store these numbered words in a safe location:\n\n${seedwords6x4}" 12 76
    whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
    if [ $? -eq 1 ]; then
      ack=1
    fi
  done

fi

# Results will be stored on memory cache:
# /var/cache/raspiblitz/seed-import.results
if [ ${mode} = "seed-import-gui" ]; then

  # fake seed 24 words for testing input:
  # eins zwei polizei drei vier great idea fünf sechs alte keks sieben auch gute nacht ja ja ja was ist los was ist das

  # scenario setup needs a 3rd parameter - the RESULTFILE to store results in
  RESULTFILE=$2
  if [ "${RESULTFILE}" == "" ]; then
    echo "error='missing parameter'"
    exit 1
  fi

  # prepare seed result file
  sudo rm /var/cache/raspiblitz/seed-import.results 2>/dev/null
  sudo touch /var/cache/raspiblitz/seed-import.results
  sudo chown admin:admin /var/cache/raspiblitz/seed-import.results

  # input loop for seed words
  wordsCorrect=0
  while [ ${wordsCorrect} -eq 0 ]
    do

      # prepare temp file 
      sudo rm /var/cache/raspiblitz/.seed.tmp 2>/dev/null
      sudo touch /var/cache/raspiblitz/.seed.tmp
      sudo chown admin:admin /var/cache/raspiblitz/.seed.tmp

      # dialog to enter
      dialog --backtitle "RaspiBlitz - Recover from LND seed" --inputbox "Please enter/paste the SEED WORD LIST:\n(just the words, seperated by spaces, in correct order as numbered)" 9 78 2>/var/cache/raspiblitz/.seed.tmp
      wordstring=$(cat /var/cache/raspiblitz/.seed.tmp | sed 's/[^a-zA-Z0-9 ]//g')
      sudo shred -u /var/cache/raspiblitz/.seed.tmp 2>/dev/null
      echo "processing ..."
      
      # check correct number of words
      wordcount=$(echo "${wordstring}" | wc -w)
      if [ ${wordcount} -eq 24 ]; then
          echo "OK - 24 words"
          wordsCorrect=1
      else
        whiptail --title " WARNING " \
			  --yes-button "Try Again" \
		    --no-button "Cancel" \
		    --yesno "
The word list has ${wordcount} words. But it must be 24.
Please check your list and try again.

Best is to write words in an external editor 
and then copy and paste them into the dialog.

The word list should look like this:
wordone wordtwo wordthree ...

" 16 52

	      if [ $? -eq 1 ]; then
          clear
          echo "# CANCEL empty results in: ${RESULTFILE}"
          exit 1
	      fi
      fi
    done

  # ask if seed was protected by password D
  passwordD=""
  dialog --title "SEED PASSWORD" --yes-button "No extra Password" --no-button "Yes" --yesno "
Are your seed words protected by an extra password?

During wallet creation its an option to set an extra password
to protect the seed words. Most users did not set this.
  " 11 65
  if [ $? -eq 1 ]; then
    sudo rm /var/cache/raspiblitz/.pass.tmp 2>/dev/null
    sudo touch /var/cache/raspiblitz/.pass.tmp
    sudo chown admin:admin /var/cache/raspiblitz/.pass.tmp
    sudo /home/admin/config.scripts/blitz.password.sh set x "Enter extra Password D" /var/cache/raspiblitz/.pass.tmp empty-allowed
    passwordD=$(sudo cat /var/cache/raspiblitz/.pass.tmp)
    sudo shred -u /var/cache/raspiblitz/.pass.tmp 2>/dev/null
  fi

  # writing result file data
  clear
  echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
  echo "seedWords='${wordstring}'" >> $RESULTFILE
  echo "seedPassword='${passwordD}'" >> $RESULTFILE
  exit 0

fi

echo "error='unknown parameter'"
exit 1
