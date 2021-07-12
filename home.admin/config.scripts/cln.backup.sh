#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# ---------------------------------------------------"

 echo "# SEED WORDS"
 echo "# ---------------------------------------------------"
 echo "# cln.backup.sh seed-export-gui [lndseeddata]"
 echo "# cln.backup.sh seed-import-gui [resultfile]"
 exit 1
fi

# 1st PARAMETER action
mode="$1"


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
