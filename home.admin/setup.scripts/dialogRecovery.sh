#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

whiptail --title " RASPIBLITZ RECOVERY " --yes-button "Start Recovery" --no-button "Other Options" --yesno "We found data from an existing RaspiBlitz on your HDD/SSD.

You can start RECOVERY now to freshly build your system to this old configuration. This process is often used to repair broken features or clean the system up.

You will need to set a new Password A for the SSH login. All your channels will stay open and other passwords will stay the same.

Please make sure to have your seed words & static channel backup file (just in case).

Do you want to start RECOVERY of your RaspiBlitz now?
      " 18 65

result=$?
echo "result($result)"