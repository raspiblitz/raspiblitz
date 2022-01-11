#!/bin/bash

# TODO: also the raspiblitz-migration & other-node-migration might need to be adapted to work with an already mounted HDD later

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source $SETUPFILE

#########################
# Parameters

# 1st PARAMATER migrationOS: [raspiblitz|mynode|umbrel|citadel]
migrationOS="$1"
if [ "${migrationOS}" != "raspiblitz" ] && [ "${migrationOS}" != "mynode" ] && [ "${migrationOS}" != "umbrel" ] && [ "${migrationOS}" != "citadel" ]; then
    echo "# FAIL: the given migrationOS '${migrationOS}' is not supported yet"
    exit 1
fi  

# 2nd PARAMATER migrationMode (optional): [normal|outdatedLightning]
migrationMode="$2"
if [ "${migrationMode}" = "" ]; then
  migrationMode="normal"
fi
if [ "${migrationMode}" != "normal" ] && [ "${migrationMode}" != "outdatedLightning" ]; then
    echo "# FAIL: the given migrationMode '${migrationMode}' is not supported yet"
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
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "multiple" ]; then
        echo "!! WARNING !!"
        echo "There are multiple lnd-rescue files in directory ${defaultUploadPath}"
        echo "Make sure you upload only one tar.gz-file and start again."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      elif [ "${error}" == "invalid" ]; then
        echo "!! WARNING !!"
        echo "The file uploaded is not a valid (complete upload failed or not correct file)."
        echo "PRESS ENTER to continue & retry ... or 'x'+ ENTER to cancel"
        read keyRetry
      else
        # create no result file and exit
        echo "!! WARNING !! Unknown State (report to devs) error(${error})"
        exit 1
      fi

      if [ "${keyRetry}" == "x" ] || [ "${keyRetry}" == "X" ] || [ "${keyRetry}" == "'x'" ]; then
        # create no result file and exit
        echo "# USER CANCEL"
        exit 1
      fi
  done

  # migration OS & Version were already set earlier in setup process - now add migration filename
  echo "migrationFile='${filename}'" >> $SETUPFILE
  echo "chain='main'" >> $SETUPFILE
  exit 0

fi

####################################################
# WARNING: OUTDATED LIGHTNING
# in case lightning version of RaspiBlitz is too old
####################################################

  # outdated warning
  if [ "${migrationMode}" == "outdatedLightning" ]; then

    whiptail --title " MIGRATION WARNING " --yes-button "Stop&Shutdown" --no-button "Try Anyway" --yesno " 

RaspiBlitz might run an too old of an lightning version to migrate your nodes
channels database automatically. You have now two options:

1) Shutdown, keep old Node system until RaspiBlitz offers an updated version
2) Ignore this warning and try your luck (not recommended)

      " 16 58

  result=$?
  echo "${result}"
  if [ "$?result" != "1" ]; then
    # user cancel - signal by exit code
    exit 1
  fi

  fi

####################################################
# UMBREL
# migrating from Umbrel to RaspiBlitz
####################################################

if [ "${migrationOS}" == "umbrel" ]; then

  # infodialog
  whiptail --title " UMBREL --> RASPIBLITZ " --yes-button "Start Migration" --no-button "No+Shutdown" --yesno "RaspiBlitz found data from UMBREL

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your UMBREL seed words & static channel backup file (just in case). Also any data of additional apps you had installed on UMBREL might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58

  if [ "$?" != "0" ]; then
    # user cancel - signal by exit code
    exit 1
  fi
  
  # signal that user wants to proceed with migration
  exit 0

fi

####################################################
# CITADEL
# migrating from Citadel to RaspiBlitz
####################################################

if [ "${migrationOS}" == "citadel" ]; then

  # infodialog
  whiptail --title " CITADEL --> RASPIBLITZ " --yes-button "Start Migration" --no-button "No+Shutdown" --yesno "RaspiBlitz found data from CITADEL

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your CITADEL seed words & static channel backup file (just in case). Also any data of additional apps you had installed on CITADEL might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58

  if [ "$?" != "0" ]; then
    # user cancel - signal by exit code
    exit 1
  fi
  
  # signal that user wants to proceed with migration
  exit 0

fi

####################################################
# MYNODE
# migrating from myNode to RaspiBlitz
####################################################

if [ "${migrationOS}" == "mynode" ]; then

  # infodialog
  whiptail --title " MYNODE --> RASPIBLITZ " --yes-button "Start Migration" --no-button "No+Shutdown" --yesno "RaspiBlitz found data from MYNODE

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your MYNODE seed words & static channel backup file (just in case). Also any data of additional apps you had installed on MYNODE might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58

  if [ "$?" != "0" ]; then
    # user cancel - signal by exit code
    exit 1
  fi

  # signal that user wants to proceed with migration
  exit 0

fi

echo "FAIL: Exited in unknown state from migration dialog."
exit 1