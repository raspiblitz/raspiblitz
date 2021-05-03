#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source $SETUPFILE

###################
# ENTER NAME
###################

# temp file for password results
_temp="/var/cache/raspiblitz/temp/.temp.tmp"

# ask for name of RaspiBlitz
result=""
while [ ${#result} -eq 0 ]
  do
    l1="Please enter the name of your new RaspiBlitz:\n"
    l2="one word, keep characters basic & not too long"
    dialog --backtitle "RaspiBlitz - Setup" --inputbox "$l1$l2" 11 52 2>$_temp
    result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
    sudo rm $_temp
  done

# store name in setup state
echo "hostname=${result}" >> $SETUPFILE