# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source $SETUPFILE

# flags for sub dialogs after choice
uploadRESCUE=0
enterSEED=0

OPTIONS=()
OPTIONS+=(NEW "Setup a brand new Lightning Node (DEFAULT)")
OPTIONS+=(OLD "I had an old Node I want to recover/restore")
CHOICE=$(dialog --backtitle "RaspiBlitz" --clear --title "LND Setup" --menu "LND Data & Wallet" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

if [ "${CHOICE}" == "NEW" ]; then

  # clear setup state from all fomer possible choices (previous loop)
  sudo sed -i '/^setPasswordA=/d' $SETUPFILE
  sudo sed -i '/^setPasswordB=/d' $SETUPFILE
  sudo sed -i '/^setPasswordC=/d' $SETUPFILE

  # mark all passwords to be set at the end
  echo "setPasswordA=1" >> $SETUPFILE
  echo "setPasswordB=1" >> $SETUPFILE
  echo "setPasswordC=1" >> $SETUPFILE

elif [ "${CHOICE}" == "OLD" ]; then

  CHOICE=""
  while [ "${CHOICESUB}" == "" ]
  do

    # get more details what kind of old lightning wallet user has
    OPTIONS=()
    OPTIONS+=(CLNRESCUE "CLN tar.gz-Backupfile (BEST)")
    OPTIONS+=(ONLYSEED "Only Seed Word List (FALLBACK)")
    CHOICESUB=$(dialog --backtitle "RaspiBlitz" --clear --title "RECOVER CLN DATA & WALLET" --menu "Data you have to recover from?" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

    if [ "${CHOICESUB}" == "CLNRESCUE" ]; then

      # just activate LND rescue upload
      uploadRESCUE=1

      # clear setup state from all fomer possible choices (previous loop)
      sudo sed -i '/^setPasswordA=/d' $SETUPFILE
      sudo sed -i '/^setPasswordB=/d' $SETUPFILE
      sudo sed -i '/^setPasswordC=/d' $SETUPFILE

      # dont set password c anymore - mark the rest
      echo "setPasswordA=1" >> $SETUPFILE
      echo "setPasswordB=1" >> $SETUPFILE

    elif [ "${CHOICESUB}" == "ONLYSEED" ]; then

      # let people know about just seed backup
      whiptail --title "IMPORTANT INFO" --yes-button "JUST SEED" --no-button "Go Back" --yesno "
Using JUST SEED WORDS will only recover your on-chain funds.
To recover also your channel funds a complete rescue-backup
from your old node would be recommended.
      " 11 65
      
      if [ $? -eq 1 ]; then
        # when user wants to go back
        CHOICESUB=""
      else
        # activate SEED input & SCB upload
        enterSEED=1

        # clear setup state from all fomer possible choices (previous loop)
        sudo sed -i '/^setPasswordA=/d' $SETUPFILE
        sudo sed -i '/^setPasswordB=/d' $SETUPFILE
        sudo sed -i '/^setPasswordC=/d' $SETUPFILE

        # mark all passwords to be set at the end
        echo "setPasswordA=1" >> $SETUPFILE
        echo "setPasswordB=1" >> $SETUPFILE
        echo "setPasswordC=1" >> $SETUPFILE

      fi

    else
       # user cancel - signal to outside app by exit code (2 = submenu)
       exit 2
    fi

  done

else
  # user cancel - signal to outside app by exit code (1 = mainmenu)
  exit 1
fi

# UPLOAD LND RESCUE FILE dialog (if activated by dialogs above)
if [ ${uploadRESCUE} -eq 1 ]; then

  # run upload dialog and get result
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  echo "TODO: cln.backup.sh cln-import-gui"
  sleep 8
  #/home/admin/config.scripts/cln.backup.sh cln-import-gui setup $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null

  # if user canceled upload
  if [ "${clnrescue}" == "" ]; then
    # signal cancel to the calling script by exit code (3 = exit on lndrescue)
    exit 3
  fi

  # clear setup state from all fomer possible choices (previous loop)
  sudo sed -i '/^clnrescue=/d' $SETUPFILE

  # store result in setup state
  echo "clnrescue='${lndrescue}'" >> $SETUPFILE
fi

# INPUT LIGHTNING SEED dialog (if activated by dialogs above)
if [ ${enterSEED} -eq 1 ]; then

  # start seed input and get results
  _temp="/var/cache/raspiblitz/.temp.tmp"
  clear
  echo "TODO: cln.backup.sh seed-import-gui"
  sleep 8
  #/home/admin/config.scripts/cln.backup.sh seed-import-gui $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null

  # if user canceled the seed input
  if [ "${seedWords}" == "" ]; then
    # signal cancel to the calling script by exit code (4 = exit on seedwords)
    exit 4
  fi

  # clear setup state from all fomer possible choices (previous loop)
  sudo sed -i '/^seedWords=/d' $SETUPFILE
  sudo sed -i '/^seedPassword=/d' $SETUPFILE

  # write the seed data into the setup state
  echo "seedWords='${seedWords}'" >> $SETUPFILE
fi