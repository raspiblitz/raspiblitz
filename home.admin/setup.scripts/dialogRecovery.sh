#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

whiptail --title " RASPIBLITZ RECOVERY " --yes-button "Start Recovery" --no-button "Other Options" --yesno "We found data from an existing RaspiBlitz on your HDD/SSD.

You can now start RECOVERY to freshly build your system based on existing configuration & data. This process is often used to repair broken features or clean the system up.

You will need to set a new Password A for the SSH login. All other passwords will stay the same and channels will stay open.

Please make sure to have your seed words & static channel backup file (just in case).

Do you want to start RECOVERY of your RaspiBlitz now?
      " 20 68

if [ "$?" == "0" ]; then
    # 0 --> run recover
    exit 0
else
    # 1 --> other options
    exit 1
fi