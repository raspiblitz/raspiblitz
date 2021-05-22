#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/_version.info
source /home/admin/raspiblitz.info

whiptail --title " RASPIBLITZ UPDATE " --yes-button "Start Update" --no-button "Other Options" --yesno "We found data from an old RaspiBlitz on your HDD/SSD.

You can start now the UPDATE to version ${codeVersion}.

You will need to set a new Password A for the SSH login. All your channels will stay open and other passwords will stay the same.

Please make sure to have your seed words & static channel backup file (just in case).

Do you want to start UPDATE of your RaspiBlitz now?
      " 18 65

if [ "$?" == "0" ]; then
    # 0 --> run recover
    exit 0
else
    # 1 --> other options
    exit 1
fi