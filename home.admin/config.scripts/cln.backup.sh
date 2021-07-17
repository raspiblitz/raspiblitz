#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# ---------------------------------------------------"
 echo "# CLN RESCUE FILE (tar.gz of complete cln directory)"
 echo "# ---------------------------------------------------"
 echo "# cln.backup.sh cln-export"
 echo "# cln.backup.sh cln-export-gui"
 echo "# cln.backup.sh cln-import [file]"
 echo "# cln.backup.sh cln-import-gui [setup|production] [?resultfile]"
 echo "# ---------------------------------------------------"
 echo "# SEED WORDS"
 echo "# ---------------------------------------------------"
 echo "# cln.backup.sh seed-export-gui [lndseeddata]"
 echo "# cln.backup.sh seed-import-gui [resultfile]"
 exit 1
fi

# 1st PARAMETER action
mode="$1"

################################
# CLN RESCUE FILE - EXPORT
################################

if [ ${mode} = "cln-export" ]; then

  echo "# *** CLN.RESCUE --> BACKUP"
  downloadPath="/home/admin"
  fileowner="admin"

  # stop LND
  echo "# Stopping cln..."
  sudo systemctl stop lightningd
  sleep 5
  echo "# OK"
  echo 

  # add cln version info into lnd dir (to detect needed updates later)
  clnVersion=$(sudo -u bitcoin lncli getinfo | jq -r ".version" | cut -d ' ' -f1)
  sudo rm /mnt/hdd/app-data/.lightning/version.info 2>/dev/null
  echo "${clnVersion}" > /home/admin/cln.version.info
  sudo mv /home/admin/cln.version.info /mnt/hdd/app-data/.lightning/version.info
  sudo chown bitcoin:bitcoin /mnt/hdd/app-data/.lightning/version.info

  # zip it
  sudo tar -zcvf ${downloadPath}/cln-rescue.tar.gz /mnt/hdd/app-data/.lightning 1>&2
  sudo chown ${fileowner}:${fileowner} ${downloadPath}/cln-rescue.tar.gz 1>&2

  # delete old backups
  rm ${downloadPath}/cln-rescue-*.tar.gz 2>/dev/null 1>/dev/null

  # name with md5 checksum
  md5checksum=$(md5sum ${downloadPath}/cln-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv ${downloadPath}/cln-rescue.tar.gz ${downloadPath}/cln-rescue-${md5checksum}.tar.gz 1>&2
  byteSize=$(ls -l ${downloadPath}/cln-rescue-${md5checksum}.tar.gz | awk '{print $5}')

  # check file size
  if [ ${byteSize} -lt 100 ]; then
    echo "error='backup is empty'"
    exit 1
  fi

  # output result data
  echo "# cln service is stopped for security"
  echo "filename='${downloadPath}/lnd-rescue-${md5checksum}.tar.gz'"
  echo "fileowner='${fileowner}'"
  echo "size=${byteSize}"
  exit 0
fi

if [ ${mode} = "lnd-export-gui" ]; then

  # create lnd rescue file
  source <(/home/admin/config.scripts/cln.backup.sh cln-export)
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
    whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "C-Lightning Wallet got created. Store these numbered words in a safe location:\n\n${seedwords6x4}" 12 76
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
      dialog --backtitle "RaspiBlitz - C-lightning Recover" --inputbox "Please enter/paste the SEED WORD LIST:\n(just the words, seperated by spaces, in correct order as numbered)" 9 78 2>/var/cache/raspiblitz/.seed.tmp
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

The Word list should look like this:
wordone wordtweo wordthree ...

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
  echo "# result in: ${RESULTFILE} (remember to make clean delete once processed)"
  echo "seedWords='${wordstring}'" >> $RESULTFILE
  echo "seedPassword='${passwordD}'" >> $RESULTFILE
  exit 0

fi

echo "error='unknown parameter'"
exit 1
