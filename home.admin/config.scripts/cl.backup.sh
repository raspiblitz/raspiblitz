#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo
 echo "---------------------------------------------------"
 echo "CL RESCUE FILE (tar.gz of complete cl directory)"
 echo "---------------------------------------------------"
 echo "cl.backup.sh cl-export"
 echo "cl.backup.sh cl-export-gui"
 echo "cl.backup.sh cl-import [file]"
 echo "cl.backup.sh cl-import-gui [setup|production] [?resultfile]"
 echo "---------------------------------------------------"
 echo "SEED WORDS"
 echo "---------------------------------------------------"
 echo "cl.backup.sh seed-export-gui [clseeddata]"
 echo "cl.backup.sh seed-import-gui [resultfile]"
 echo "---------------------------------------------------"
 echo "RECOVERY"
 echo "---------------------------------------------------"
 echo "cl.backup.sh [mainnet|signet|testnet] recoverymode [on|off|status] <-rescanbockheight|rescandepth>"
 echo
 exit 1
fi

# 1st PARAMETER [mainnet|signet|testnet]
if [ "$1" == "mainnet" ] || [ "$1" == "testnet" ] || [ "$1" == "signet" ]; then

  # prepare all chain dependent variables
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)
  mode="$2"

  ################################
  # RECOVERY
  ################################

  # c-lightning is considered in "recoverymode" when it is scanning the chain
  # and getinfo -H shows:  'warning_lightningd_sync=Still loading latest blocks from bitcoind.'
  # and 'blockheight=lower-than-in-bitcoind'

  if [ ${mode} = "recoverymode" ]; then

    # check if started with sudo
    if [ "$EUID" -ne 0 ]; then 
      echo "error='run as root'"
      exit 1
    fi

    # status
    recoverymodeStatus=$(grep -c "^rescan=" < "${CLCONF}")
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

      # clean
      sed -i 's/^rescan=.*//g' "${CLCONF}"
      sed -i 's/^log-level=.*//g' "${CLCONF}"

      # activate rescan in cl config
      if [ $# -gt 3 ]; then
        scanFrom="$4"
      else
        # scan from block 700000 by default
        scanFrom="-700000"
      fi
      echo "# activating recovery mode ..."
      echo "rescan=${scanFrom}" | tee -a  "${CLCONF}"
      echo "# setting log-level=debug ..."
      echo "log-level=debug" | tee -a  "${CLCONF}"
      echo "# OK - restart/reboot needed for: ${netprefix}lightningd.service"
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
      sed -i 's/^rescan=.*//g' "${CLCONF}"
      sed -i 's/^log-level=.*//g' "${CLCONF}"
      echo "# setting log-level=info (default) ..."
      echo "log-level=info" | tee -a  "${CLCONF}"
      echo "# OK - restart/reboot needed for: ${netprefix}lightningd.service"
      exit 0
    fi

    # parameter fallback
    echo "error='unknown parameter'"
    exit 1

  fi

fi

# 1st PARAMETER action
mode="$1"

################################
# CL RESCUE FILE - EXPORT
################################

if [ ${mode} = "cl-export" ]; then

  echo "# *** CL.RESCUE --> BACKUP"
  downloadPath="/home/admin"
  fileowner="admin"

  # stop
  echo "# Stopping cl..."
  sudo systemctl stop lightningd 1>/dev/null
  if grep -Eq "^tcl=on" /mnt/hdd/raspiblitz.conf; then
    echo "# stopping tcl..."
    sudo systemctl stop tlightningd 1>/dev/null
  fi
  if grep -Eq "^scl=on" /mnt/hdd/raspiblitz.conf; then
    echo "# stopping scl..."
    sudo systemctl stop slightningd 1>/dev/null
  fi
  sleep 5
  echo "# OK"
  echo 

  # add cl version info into lnd dir (to detect needed updates later)
  clVersion=$(sudo -u bitcoin lightning-cli --version | cut -d '-' -f1 | cut -d 'v' -f2)
  sudo rm /mnt/hdd/app-data/.lightning/version.info 2>/dev/null
  echo "${clVersion}" > /home/admin/cl.version.info
  sudo mv /home/admin/cl.version.info /mnt/hdd/app-data/.lightning/version.info
  sudo chown bitcoin:bitcoin /mnt/hdd/app-data/.lightning/version.info

  # zip it
  sudo tar -zcvf ${downloadPath}/cl-rescue.tar.gz /mnt/hdd/app-data/.lightning 1>&2
  sudo chown ${fileowner}:${fileowner} ${downloadPath}/cl-rescue.tar.gz 1>&2

  # delete old backups
  # rm ${downloadPath}/cl-rescue-*.tar.gz 2>/dev/null 1>/dev/null

  # name with md5 checksum
  md5checksum=$(md5sum ${downloadPath}/cl-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv ${downloadPath}/cl-rescue.tar.gz ${downloadPath}/cl-rescue-${md5checksum}.tar.gz 1>&2
  byteSize=$(ls -l ${downloadPath}/cl-rescue-${md5checksum}.tar.gz | awk '{print $5}')

  # check file size
  if [ ${byteSize} -lt 100 ]; then
    echo "error='backup is empty'"
    exit 1
  fi

  # output result data
  echo "# cl service is stopped for security"
  echo "filename='${downloadPath}/cl-rescue-${md5checksum}.tar.gz'"
  echo "fileowner='${fileowner}'"
  echo "size=${byteSize}"
  exit 0
fi

if [ ${mode} = "cl-export-gui" ]; then
  echo "# Create the CL rescue file ..."
  source <(/home/admin/config.scripts/cl.backup.sh cl-export)
  if [ "${error}" != "" ]; then
    echo "error='${error}'"
    exit 1
  fi

  # get local ip info
  source <(/home/admin/config.scripts/internet.sh status local)

  # offer SFTP for download
  clear
  echo
  echo "*******************************************"
  echo "* DOWNLOAD THE CORE LIGHTNING RESCUE FILE *"
  echo "*******************************************"
  echo 
  echo "ON YOUR MAC & LINUX LAPTOP - RUN IN NEW TERMINAL:"
  echo "sftp '${fileowner}@${localip}:${filename}' ./"
  echo "ON WINDOWS USE:"
  echo "sftp ${fileowner}@${localip}:${filename} ."
  echo
  echo "Use password A to authenticate file transfer."
  echo "Check for correct file size after transfer: ${size} byte"
  echo
  echo "BEWARE: Your Lightning node is now stopped. It's safe to backup the data and"
  echo "restore it on a fresh RaspiBlitz. But once this Lightning node gets started"
  echo "again or rebooted, it's not advised to restore the backup file because"
  echo "it would contain outdated channel data and can lead to loss of channel funds."
  exit 0
fi

################################
# CL RESCUE FILE - IMPORT
################################

if [ ${mode} = "cl-import" ]; then

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

  # stop
  echo "# stopping cl..."
  sudo systemctl stop lightningd 1>/dev/null
  if grep -Eq "^tcl=on" /mnt/hdd/raspiblitz.conf; then
    echo "# stopping tcl..."
    sudo systemctl stop tlightningd 1>/dev/null
  fi
  if grep -Eq "^scl=on" /mnt/hdd/raspiblitz.conf; then
    echo "# stopping scl..."
    sudo systemctl stop slightningd 1>/dev/null
  fi
  sleep 5

  # clean DIR
  echo "# cleaning old CL data ..."
  sudo rm -r /mnt/hdd/app-data/.lightning/* 1>/dev/null 2>/dev/null

  # unpack zip
  echo "# restoring CL data from ${filename} ..."
  sudo tar -xf ${filename} -C / 1>/dev/null
  sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/.lightning 1>/dev/null

  echo "# DONE - lightningd service is still stopped - start manually with command:"
  echo "# sudo systemctl start lightningd"
  exit 0

fi

if [ ${mode} = "cl-import-gui" ]; then

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
      echo "*****************************************"
      echo "* UPLOAD THE CORE LIGHTNING RESCUE FILE *"
      echo "*****************************************"
      echo "If you have a cl-rescue backup file on your laptop you can now"
      echo "upload it and restore your latest Core Lightning state."
      echo
      echo "CAUTION: Don't restore outdated states - risk of loosing funds!"
      echo
      echo "To make upload open a new terminal on your laptop,"
      echo "change into the directory where your cl-rescue file is and"
      echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
      echo "sftp -r ./cl-rescue-*.tar.gz ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
      echo
      echo "Use ${passwordInfo} to authenticate file transfer."
      echo "PRESS ENTER when upload is done"
      read key

      # check upload (will return filename or error)
      source <(sudo /home/admin/config.scripts/blitz.upload.sh check-upload cl-rescue)
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
        echo "There are multiple cl-rescue files in directory ${defaultUploadPath}"
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

  # in setup scenario the final import is happening during provision
  if [ "${scenario}" == "setup" ]; then
    # just add clrescue filename to give file
    echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
    echo "clrescue='${filename}'" >> $RESULTFILE
    exit 0
  fi

  # in production now start restoring CL data based on file
  source /mnt/hdd/raspiblitz.conf
  
  # ask security question before deleting old wallet
  echo "WARNING: This will delete/overwrite the Core Lightning state/funds of this RaspiBlitz."
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
  echo "OK deleting old CL data & restoring imported rescue file ..."
  source <(sudo /home/admin/config.scripts/cl.backup.sh cl-import ${filename})

  # TODO: check if update of CL is needed (see detailes in cl-import) for edge case

  # turn off auto-unlock if activated because password c might now change
  /home/admin/config.scripts/cl.hsmtool.sh autounlock-off

  # detect if the imported hsm_secret is encrypted
  # use the variables for the default network 
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl)
  hsmSecretPath="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"
  # check if encrypted
  trap 'rm -f "$output"' EXIT
  output=$(mktemp -p /dev/shm/)
  echo "test" | sudo -u bitcoin lightning-hsmtool decrypt "$hsmSecretPath" \
   2> "$output"
  if [ "$(grep -c "hsm_secret is not encrypted" < "$output")" -gt 0 ];then
    echo "# The hsm_secret is not encrypted"
    echo "# Record in raspiblitz.conf"
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clEncryptedHSM "off"
  else
    cat $output
    echo "# Starting cl.hsmtool.sh unlock"
    /home/admin/config.scripts/cl.hsmtool.sh unlock $CHAIN
  fi

  # set the lightningd service file on each active network
  # init backup plugin, restart cl
  if [ "${cl}" == "on" ] || [ "${cl}" == "1" ]; then
    /home/admin/config.scripts/cl.install-service.sh mainnet
    /home/admin/config.scripts/cl-plugin.backup.sh on mainnet
  fi
  if [ "${tcl}" == "on" ] || [ "${tcl}" == "1" ]; then
    /home/admin/config.scripts/cl.install-service.sh testnet
    /home/admin/config.scripts/cl-plugin.backup.sh on testnet
  fi
  if [ "${scl}" == "on" ] || [ "${scl}" == "1" ]; then
    /home/admin/config.scripts/cl.install-service.sh signet
    /home/admin/config.scripts/cl-plugin.backup.sh on signet
  fi
 
  # give final info
  echo
  echo "# DONE - lightningd is now starting"
  echo "# Check that CL is starting up correctly and your old channels & funds are restored."
  echo "# Take into account that some channels might have been force closed in the meanwhile."
  echo
  exit 0
fi

####################################
# SEED WORDS - GUI PARTS
####################################

if [ ${mode} = "seed-export-gui" ]; then

  # use text snippet for testing:
  # 

  # 2nd PARAMETER: cl seed data
  seedwords6x4=$2
  if [ "${seedwords6x4}" == "" ]; then
    echo "error='missing parameter'"
    exit 1 
  fi

  ack=0
  while [ ${ack} -eq 0 ]
  do
    whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "Created a new Core Lightning wallet. Store these numbered 24 words in a safe location:\n\n${seedwords6x4}" 13 76
    whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
    if [ $? -eq 1 ]; then
      ack=1
    fi
  done
  exit 0
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
      dialog --backtitle "RaspiBlitz - Recover from Core Lightning seed" --inputbox "Please enter/paste the SEED WORD LIST:\n(just the words, seperated by spaces, in correct order as numbered)" 9 78 2>/var/cache/raspiblitz/.seed.tmp
      wordstring=$(cat /var/cache/raspiblitz/.seed.tmp | sed 's/[^a-zA-Z0-9 ]//g')
      sudo shred -u /var/cache/raspiblitz/.seed.tmp 2>/dev/null
      echo "processing ..."
      
      # check correct number of words
      wordcount=$(echo "${wordstring}" | wc -w)
      if [ ${wordcount} -eq 24 ]; then

        # check if words are valid seed
        source <(python /home/admin/config.scripts/blitz.mnemonic.py test "${wordstring}")
        if [ "${valid}" == "0" ]; then
          whiptail --title " WARNING " --yes-button "Try Again" --no-button "Cancel" --yesno "
The word list has 24 words BUT its not a
valid seed word list by our test.

Please check for typos.

" 12 52
	        if [ $? -eq 1 ]; then
            clear
            echo "# CANCEL empty results in: ${RESULTFILE}"
            exit 1
	        fi
        else
          echo "OK - 24 words"
          wordsCorrect=1
        fi
      else
        whiptail --title " WARNING " \
			  --yes-button "Try Again" \
		    --no-button "Cancel" \
		    --yesno "
The word list has ${wordcount} words. But it must be 24.
Please check your list and try again.

Best is to write words in external editor 
and then copy and paste them into dialog.

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

  # dont ask for password D (seed password) because raspiblitz never had that option for cl
  passwordD=""

  # writing result file data
  clear
  echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
  echo "seedWords='${wordstring}'" >> $RESULTFILE
  echo "seedPassword='${passwordD}'" >> $RESULTFILE
  exit 0

fi

echo "error='unknown parameter'"
exit 1
