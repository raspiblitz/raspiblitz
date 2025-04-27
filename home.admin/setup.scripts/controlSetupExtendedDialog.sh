#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info
# get values from cache

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"

# load setup state
source ${SETUPFILE}

if [ "${hddMigration}" = "1" ]; then

  # ask for upload file

  exit 0
fi

# break loop if no matching if above
/home/admin/_cache.sh set state "error"
exit 1