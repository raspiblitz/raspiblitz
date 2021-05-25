#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source ${SETUPFILE}

############################################
# SHOW SEED WORDS AFTER SETUP
if [ "${setupPhase}" == "setup" ]; then

  echo "Write down your seedwords: ${seedwords6x4NEW}"
  echo "PRESS ENTER"
  read key

fi

############################################
# SETUP DONE CONFIRMATION (Konfetti Moment)

# when coming from fresh setup
if [ "${setupPhase}" == "setup" ]; 

  echo "Hooray :) Everything is Setup!"
  echo "PRESS ENTER"
  read key

elif [ "${setupPhase}" == "migration" ]; then

  echo "Hooray :) Your Migration to RaspiBlitz is Done!"
  echo "PRESS ENTER"
  read key

else
  echo "Missing Final Done Dialog for: ${setupPhase}"
  echo "PRESS ENTER"
  read key
fi