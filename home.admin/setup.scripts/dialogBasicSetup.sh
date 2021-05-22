#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/_version.info

# chose how to setup node (fresh or from a upload backup)
OPTIONS=()
OPTIONS+=(FRESHSETUP "Setup a new RaspiBlitz")
OPTIONS+=(FROMBACKUP "Upload Migration Backup")
OPTIONS+=(SHUTDOWN "Shutdown without Changes")
CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz ${codeVersion} - Setup" \
                --title "⚡ Welcome to your RaspiBlitz ⚡" \
                --menu "\nChoose how you want to setup your RaspiBlitz: \n " \
                13 64 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
clear
case $CHOICE in
        FRESHSETUP)
            # 0 --> FRESH SETUP 
            exit 0;
            ;;
        FROMBACKUP)
            # 1 --> UPLOAD MIGRATION BACKUP
            exit 1
            ;;
        SHUTDOWN)
            # 2 --> SHUTDOWN
            exit 2
            ;;
        *)
            # 3 --> ESC/CANCEL = EXIT TO TERMINAL
            clear
            echo "Exit to Terminal from RaspiBlitz Setup ..."
            echo "Command to return to Setup --> raspiblitz"
            exit  3
esac