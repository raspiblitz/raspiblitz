#!/bin/bash

# TODO: also the raspiblitz-migration & other-node-migration might need to be adapted to work with an already mounted HDD later

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/raspiblitz.setup"
source $SETUPFILE

#########################
# Parameters
# this is useful for testing the dialog outside of the setup process
# normally migrationOS & migrationVersion are provided by raspiblitz.info or raspiblitz.setup

# 1st PARAMATER (optional): [raspiblitz|mynode|umbrel]
if [ "${migrationOS}" == "" ]; then
  migrationOS="$1"
fi  

# 2nd PARAMATER (optional): the version of the former fullnode OS if available
if [ "${migrationVersion}" == "" ]; then
  migrationVersion="$2"
fi

# check parameter values
if [ "${migrationOS}" != "raspiblitz" ] && [ "${migrationOS}" != "mynode" ] && [ "${migrationOS}" != "umbrel" ]; then
    echo "# FAIL: the given migrationOS '${migrationOS}' is not supported yet"
    exit 1
fi

####################################################
# RASPIBLITZ
# migrating from other hardware with migration file
####################################################

if [ "${migrationOS}" == "raspiblitz" ]; then

  # get defaultUploadPath, localIP, etc
  source <(sudo /home/admin/config.scripts/blitz.upload.sh prepare-upload)

  filename=""
  while [ "${filename}" == "" ]
    do

      clear
      echo "*****************************"
      echo "* UPLOAD THE MIGRATION FILE *"
      echo "*****************************"
      echo "If you have a migration file on your laptop you can now"
      echo "upload it and restore on the new HDD/SSD."
      echo
      echo "ON YOUR LAPTOP open a new terminal and change into"
      echo "the directory where your migration file is and"
      echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
      echo "scp -r ./raspiblitz-*.tar.gz ${defaultUploadUser}@${localip}:${defaultUploadPath}/"
      echo ""
      echo "Use password 'raspiblitz' to authenticate file transfer."
      echo "PRESS ENTER when upload is done."
      read key

      # check upload (will return filename or error)
      source <(sudo /home/admin/config.scripts/blitz.upload.sh check-upload migration)
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
        echo "!! WARNING !! Unknown State (report to devs) error(${error})"
        exit 1
      fi
  done

  # further checks and unpacking will be done when migration is processed (not part of dialog)
  echo "OK: Migration file was imported - will process after password reset"
  sleep 4
  # migration OS & Version were already set earlier in setup process - now add migration filename
  echo "migrationFile='${filename}'" >> $SETUPFILE
  # user needs to reset password A
  echo "setPasswordA=1" >> $SETUPFILE
  exit 0

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

  if [ "$?" != "0" ]; then
    # user cancel - signal by exit code
    exit 1
  fi

  # write migration info
  echo "migrationOS='umbrel'" >> $SETUPFILE
  echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE

  # user needs to reset password A, B & C
  echo "setPasswordA=1" >> $SETUPFILE
  echo "setPasswordB=1" >> $SETUPFILE
  echo "setPasswordC=1" >> $SETUPFILE
  exit 0

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

  if [ "$?" != "0" ]; then
    # user cancel - signal by exit code
    exit 1
  fi
  # write migration info
  echo "migrationOS='mynode'" >> $SETUPFILE
  echo "migrationVersion='${migrationVersion}'" >> $SETUPFILE

  # user needs to reset password A
  echo "setPasswordA=1" >> $SETUPFILE
  echo "setPasswordB=1" >> $SETUPFILE
  echo "setPasswordC=1" >> $SETUPFILE
  exit 0

fi

echo "FAIL: Exited in unknown state from migration dialog."
exit 1