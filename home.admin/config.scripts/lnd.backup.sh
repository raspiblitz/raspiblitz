#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# ---------------------------------------------------"
 echo "# LND RESCUE FILE (tar.gz of complete lnd directory)"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh lnd-export"
 echo "# lnd.backup.sh lnd-export-gui"
 echo "# lnd.backup.sh lnd-import [file]"
 echo "# lnd.backup.sh lnd-import-gui [setup|production]"
 echo "# ---------------------------------------------------"
 echo "# STATIC CHANNEL BACKUP"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh scb-export"
 echo "# lnd.backup.sh scb-export-gui"
 echo "# lnd.backup.sh scb-import [file]"
 echo "# lnd.backup.sh scb-import-gui [setup|production]"
 echo "# ---------------------------------------------------"
 echo "# SEED WORDS"
 echo "# ---------------------------------------------------"
 echo "# lnd.backup.sh seed-export-gui [lndseeddata]"
 echo "# lnd.backup.sh seed-import-gui"
 exit 1
fi

# 1st PRAMETER action
mode="$1"

################################
# LND RESCUE FILE - EXPORT
################################

if [ ${mode} = "lnd-export" ]; then

  echo "# *** LND.RESCUE --> BACKUP"
  downloadPath="/home/admin"
  fileowner="admin"

  # stop LND
  echo "# Stopping lnd..."
  sudo systemctl stop lnd
  sleep 5
  echo "# OK"
  echo 

  # add lnd version info into lnd dir (to detect needed updates later)
  lndVersion=$(sudo -u bitcoin lncli getinfo | jq -r ".version" | cut -d ' ' -f1)
  sudo rm /mnt/hdd/lnd/version.info 2>/dev/null
  echo "${lndVersion}" > /home/admin/lnd.version.info
  sudo mv /home/admin/lnd.version.info /mnt/hdd/lnd/version.info
  sudo chown bitcoin:bitcoin /mnt/hdd/lnd/version.info

  # zip it
  sudo tar -zcvf ${downloadPath}/lnd-rescue.tar.gz /mnt/hdd/lnd 1>&2
  sudo chown ${fileowner}:${fileowner} ${downloadPath}/lnd-rescue.tar.gz 1>&2

  # delete old backups
  rm ${downloadPath}/lnd-rescue-*.tar.gz 2>/dev/null 1>/dev/null

  # name with md5 checksum
  md5checksum=$(md5sum ${downloadPath}/lnd-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv ${downloadPath}/lnd-rescue.tar.gz ${downloadPath}/lnd-rescue-${md5checksum}.tar.gz 1>&2
  byteSize=$(ls -l ${downloadPath}/lnd-rescue-${md5checksum}.tar.gz | awk '{print $5}')

  # check file size
  if [ ${byteSize} -lt 100 ]; then
    echo "error='backup is empty'"
    exit 1
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
  source <(/home/admin/config.scripts/lnd.backup.sh lnd-export)
  if [ "${error}" != "" ]; then
    echo "error='${error}'"
    exit 1
  fi

  # get local ip info
  source <(/home/admin/config.scripts/internet.sh status local)

  # offer SCP for download
  clear
  echo
  echo "****************************"
  echo "* DOWNLOAD THE RESCUE FILE *"
  echo "****************************"
  echo 
  echo "ON YOUR MAC & LINUX LAPTOP - RUN IN NEW TERMINAL:"
  echo "scp '${fileowner}@${localip}:${filename}' ./"
  echo "ON WINDOWS USE:"
  echo "scp ${fileowner}@${localip}:${filename} ."
  echo ""
  echo "Use password A to authenticate file transfer."
  echo "Check for correct file size after transfer: ${byteSize} byte"
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
  # if so just signal this in the output
  
  echo "# DONE - lnd service is still stopped - start manually with command:"
  echo "# sudo systemctl start lnd"
  exit 0

fi

if [ ${mode} = "lnd-import-gui" ]; then

  # get by second parameter if this call if happening during setup or production
  scenario=$2
  if [ "${scenario}" != "setup" ] && [ "${scenario}" != "production" ]; then
    echo "error='mising parameter'"
    exit 1
  fi

  # scenario setup needs a 3rd parameter - the SETUPFILE to store results in
  if [ "${scenario}" == "setup" ]; then
    SETUPFILE=$3
    if [ "${SETUPFILE}" == "" ]; then
      echo "error='mising parameter'"
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
      echo "**************************"
      echo "* UPLOAD THE RESCUE FILE *"
      echo "**************************"
      echo "If you have a lnd-rescue backup file on your laptop you can now"
      echo "upload it and restore the your latest LND state."
      echo
      echo "CAUTION: Dont restore old LND states - risk of loosing funds!"
      echo
      echo "To make upload open a new terminal on your laptop,"
      echo "change into the directory where your lnd-rescue file is and"
      echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
      echo "scp -r ./lnd-rescue-*.tar.gz ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
      echo ""
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
        echo "!! WARNING !!"
        echo "There was no upload found in ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry"
        read key
      elif [ "${error}" == "multiple" ]; then
        echo "!! WARNING !!"
        echo "There are multiple lnd-rescue files in directory ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry"
        read key
      elif [ "${error}" == "invalid" ]; then
        echo "!! WARNING !!"
        echo "The file uploaded is not a valid (complete upload failed or not correct file)."
        echo "PRESS ENTER to continue & retry"
        read key
      else
        echo "!! WARNING !! Unknown State (report to devs)"
        exit 1
      fi
  done

  # in setup scenario the final import is happening during provison
  if [ "${scenario}" == "setup" ]; then
    # just add lndrescue filename to give file
    echo "lndrescue='${filename}'" >> $SETUPFILE
    echo ""
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
    echo "error='mising parameter'"
    exit 1
  fi

  # scenario setup needs a 3rd parameter - the SETUPFILE to store results in
  if [ "${scenario}" == "setup" ]; then
    SETUPFILE=$3
    if [ "${SETUPFILE}" == "" ]; then
      echo "error='mising parameter'"
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
      echo "scp ./*.backup ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
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
        echo "!! WARNING !!"
        echo "There was no upload found in ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry"
        read key
      elif [ "${error}" == "multiple" ]; then
        echo "!! WARNING !!"
        echo "There are multiple lnd-rescue files in directory ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry"
        read key
      elif [ "${error}" == "invalid" ]; then
        echo "!! WARNING !!"
        echo "The file uploaded is not a valid (complete upload failed or not correct file)."
        echo "PRESS ENTER to continue & retry"
        read key
      else
        echo "!! WARNING !! Unknown State (report to devs)"
        exit 1
      fi
  done

  # in setup scenario the final import is happening during provison
  if [ "${scenario}" == "setup" ]; then
    # just add staticchannelbackup filename to give file
    echo "staticchannelbackup='${filename}'" >> $SETUPFILE
    echo ""
    exit 0
  fi

  # run import process
  echo "OK importing channel.backup file ..."
  source <(sudo /home/admin/config.scripts/lnd.backup.sh scb-import ${filename})

  # give final info
  echo "DONE - placed SCB file at /home/admin/channel.backup"
  echo "Reboot and login to trigger import."
  exit 0
fi

####################################
# SEED WORDS - GUI PARTS
####################################

 echo "# lnd.backup.sh seed-export-gui [seedwords6x4]"
 echo "# lnd.backup.sh seed-import-gui [resultfile]"

if [ ${mode} = "seed-export-gui" ]; then

  # 2nd PARAMETER: lnd seed data
  seedwords=$2
  if [ "${seedwords}" == "" ]; then
    echo "error='mising parameter'"
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
      dialog --backtitle "RaspiBlitz - LND Recover" --inputbox "Please enter/paste the SEED WORD LIST:\n(just the words, seperated by spaces, in correct order as numbered)" 9 78 2>/var/cache/raspiblitz/.seed.tmp
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

Best is to write words in external editor 
and then copy and paste them into dialog.

The Word list should look like this:
wordone wordtweo wordthree ...

" 16 52

	      if [ $? -eq 1 ]; then
          echo "# CANCEL empty results in: /var/cache/raspiblitz/seed-import.results"
          clear
          exit 1
	      fi
      fi
    done

  # ask if seed was protected by password D
  passwordD=""
  dialog --title "SEED PASSWORD" --yes-button "No extra Password" --no-button "Yes" --yesno "
Are your seed words protected by an extra password?

During wallet creation LND offers to set an extra password
to protect the seed words. Most users did not set this.
  " 11 65
  if [ $? -eq 1 ]; then
    sudo rm /var/cache/raspiblitz/.pass.tmp 2>/dev/null
    sudo touch /var/cache/raspiblitz/.pass.tmp
    sudo chown admin:admin /var/cache/raspiblitz/.pass.tmp
    sudo /home/admin/config.scripts/blitz.setpassword.sh x "Enter extra Password D" /var/cache/raspiblitz/.pass.tmp empty-allowed
    passwordD=$(sudo cat /var/cache/raspiblitz/.pass.tmp)
    sudo shred -u /var/cache/raspiblitz/.pass.tmp 2>/dev/null
  fi

  # writing result file data
  clear
  echo "# result of in mem cache: /var/cache/raspiblitz/seed-import.results"
  echo "seedwords='${wordstring}'" >> /var/cache/raspiblitz/seed-import.results
  echo "password='${passwordD}'" >> /var/cache/raspiblitz/seed-import.results
  exit 0

fi

echo "error='unknown parameter'"
exit 1
