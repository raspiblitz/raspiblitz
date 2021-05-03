#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/raspiblitz.setup"

# init SETUPFILE
rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP STATE" > $SETUPFILE

############################################
# Basic Setup (Blockchain & Lightning Impl)
# (skip if migration was auto-detected)

if [ "${migrationOS}" == "" ]; then

  /home/admin/setup/dialogBasicSetup.sh

  # on cancel - let user exit to terminal
  if [ "$?" != "0" ]; then
    echo "# you selected cancel - exited to terminal"
    echo "# to re-start setup use command --> setup"
    exit 1
  fi

fi

if [ "${migrationOS}" != "" ]; then

  ###############################################
  # MIGRATION 
  # other fullnodesOS or RaspiBlitz migration file

  echo "# Starting migration dialog ..."

  /home/admin/setup/dialogMigration.sh

  # on cancel - let user exit to terminal
  if [ "$?" != "0" ]; then
    echo "# you selected cancel - exited to terminal"
    echo "# to re-start setup use command --> setup"
    exit 1
  fi

else

  ###############################################
  # FRESH SETUP

  echo "# Starting all dialogs for fresh setup ..."

  ############################################
  # Setting Name for Node

  /home/admin/setup/dialogPasswords.sh

  ############################################
  # Lightning Wallet (new or restore) do this before passwords
  # because password C not needed if LND rescue file is uploaded

  while loop

fi

############################################
# Enter Passwords
# for fresh setup & migration

/home/admin/setup/dialogPasswords.sh

############################################
# PROCESS SETUP CHOICES
# TODO: move this part later outside of dialog controller and combine with data from WebUI

if [ "${migrationOS}" == "" ]; then

  ############################################
  # Normal Setup

  echo "# CREATING raspiblitz.conf from your setup choices"

  # prepare the config file (what will later become the raspiblitz.config)
  source /home/admin/_version.info

  CONFIGFILE="/mnt/hdd/raspiblitz.config"
  rm $CONFIGFILE 2>/dev/null
  echo "# RASPIBLITZ CONFIG FILE" > $CONFIGFILE
  echo "raspiBlitzVersion='${codeVersion}'" >> $CONFIGFILE
  echo "lcdrotate=1" >> $CONFIGFILE
  echo "lightning=${lightning}" >> $CONFIGFILE
  echo "network=${network}" >> $CONFIGFILE
  echo "chain=main" >> $CONFIGFILE
  echo "runBehindTor=on" >> $CONFIGFILE

else

  ############################################
  # Process Migration
  # TODO: move this part later outside of dialog controller and combine with data from WebUI

  echo "TODO: Process Migration"
  exit 1

fi

clear
echo "# setup dialog done - results in:"
echo "# $SETUPFILE"
echo "# $CONFIGFILE"