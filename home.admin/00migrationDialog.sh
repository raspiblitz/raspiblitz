#!/bin/bash

# TODO: also the migration might need to be adapted to work with an already mounted HDD later

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# dialog to get all data needed for migration-setup"
 echo "# 00migrationDialog.sh [raspiblitz|mynode|umbrel]"
 exit 1
fi

## get basic info
source /home/admin/raspiblitz.info

# tempfile for result of dialogs
_temp=$(mktemp -p /dev/shm/)

# prepare the setup file (that constains info just needed for the rest of setup process)
SETUPFILE="/home/admin/raspiblitz.setup"
rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP FILE" > $SETUPFILE

# flags of what passwords are to set by user
setPasswordA=1
setPasswordB=0
setPasswordC=0

# 1st PARAMATER: [raspiblitz|mynode|umbrel]
migrationOS="$1"
if [ "${migrationOS}" != "raspiblitz" ] && [ "${migrationOS}" != "mynode" ] && [ "${migrationOS}" != "umbrel" ]; then
    echo "parameter1(${migrationOS})"
    echo "error='not supported'"
    exit 1
fi

# 2nd PARAMATER (optional): the version of the former fullnode OS if available
migrationVersion="$2"

####################################################
# RASPIBLITZ
# migrating from other hardware with migration file
####################################################

if [ "${migrationOS}" == "raspiblitz" ]; then

  # write migration info
  echo "migrationOS='${migrationOS}'" >> $SETUPFILE
  echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE

  # get defaultZipPath, localIP, etc
  source <(sudo /home/admin/config.scripts/blitz.migration.sh status)

  # make sure that temp directory exists and can be written by admin
  sudo mkdir -p ${defaultZipPath}
  sudo chmod 777 -R ${defaultZipPath}

  # scp upload info
  clear
  echo
  echo "*****************************"
  echo "* UPLOAD THE MIGRATION FILE *"
  echo "*****************************"
  echo "If you have a migration file on your laptop you can now"
  echo "upload it and restore on the new HDD/SSD."
  echo
  echo "ON YOUR LAPTOP open a new terminal and change into"
  echo "the directory where your migration file is and"
  echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
  echo "scp -r ./raspiblitz-*.tar.gz admin@${localip}:${defaultZipPath}"
  echo ""
  echo "Use password 'raspiblitz' to authenticate file transfer."
  echo "PRESS ENTER when upload is done."
  read key

  countZips=$(sudo ls ${defaultZipPath}/raspiblitz-*.tar.gz 2>/dev/null | grep -c 'raspiblitz-')

  # in case no upload found
  if [ ${countZips} -eq 0 ]; then
    echo "FAIL: Was not able to detect uploaded file in ${defaultZipPath}"
    echo "Shutting down ... please make a fresh sd card & try again."
    sleep 3
    echo "shutdown=1" >> $SETUPFILE
    exit 1
  fi

  # in case of multiple files
  if [ ${countZips} -gt 1 ]; then
    echo "# FAIL: Multiple possible files detected in ${defaultZipPath}"
    echo "Shutting down ... please make a fresh sd card & try again."
    sleep 3
    echo "shutdown=1" >> $SETUPFILE
    exit 1
  fi

  # further checks and unpacking will be done when migration is processed (not part of dialog)
  echo "OK: Migration data was imported - will process after password reset"
  sleep 4

  # user needs to reset password A
  setPasswordA=1

fi

####################################################
# UMBREL
# migrating from Umbrel to RaspiBlitz
####################################################

if [ "${migrationOS}" == "umbrel" ]; then

  # infodialog
  whiptail --title " UMBREL --> RASPIBLITZ " --yes-button "Start Migration" --no-button "Shutdown" --yesno "RaspiBlitz found data from UMBREL

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your UMBREL seed words & static channel backup file (just in case). Also any data of additional apps you had installed on UMBREL might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58

  if [ $? -eq 0 ]; then
    # write migration info
    echo "migrationOS='umbrel'" >> $SETUPFILE
    echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE
  else
    # user cancel - request shutdown
    echo "shutdown=1" >> $SETUPFILE
    exit 1
  fi

  # user needs to reset password A
  setPasswordA=1
  setPasswordB=1
  setPasswordC=1

fi

####################################################
# MYNODE
# migrating from myNode to RaspiBlitz
####################################################

if [ "${migrationOS}" == "mynode" ]; then

  # infodialog
  whiptail --title " MYNODE --> RASPIBLITZ " --yes-button "Start Migration" --no-button "Shutdown" --yesno "RaspiBlitz found data from MYNODE

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your MYNODE seed words & static channel backup file (just in case). Also any data of additional apps you had installed on MYNODE might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58

  if [ $? -eq 0 ]; then
    # write migration info
    echo "migrationOS='mynode'" >> $SETUPFILE
    echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE
  else
    # user cancel - request shutdown
    echo "shutdown=1" >> $SETUPFILE
    exit 1
  fi

  # user needs to reset password A
  setPasswordA=1
  setPasswordB=1
  setPasswordC=1

fi

####################################################
# INPUT PASSWORDS (based on flags above set)

# dynamic info string on what passwords need to be changed
passwordinfo="A" # always so far
if [ ${setPasswordB} -eq 1 ]; then
  passwordinfo = "${passwordinfo}, B"
fi
if [ ${setPasswordC} -eq 1 ]; then
  passwordinfo = "${passwordinfo}, C"
fi

# basic information in RaspiBlitz passwords
dialog --backtitle "RaspiBlitz - Migration Setup" --msgbox "You will need to set new passwords.

RaspiBlitz works with 3 different passwords:
PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (RPC & Additional Apps)
PASSWORD C) Lightning Wallet Password for Unlock

You will need to set Password: ${passwordinfo}
(other passwords might stay like on your old node)

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 17 64

if [ ${setPasswordA} -eq 1 ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD A - Main User Password" $_temp
  password=$(sudo cat $_temp)
  echo "passwordA='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password A set" 7 20
fi

if [ ${setPasswordB} -eq 1 ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD B - APP Password" $_temp
  password=$(sudo cat $_temp)
  echo "passwordB='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password B set" 7 20
fi

if [ ${setPasswordC} -eq 1 ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD C - Lightning Wallet Password" $_temp
  password=$(sudo cat $_temp)
  echo "passwordC='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password C set" 7 20
fi

clear
echo "# data from dialogs stored in to be further processed:"
echo "${SETUPFILE}"
exit 0