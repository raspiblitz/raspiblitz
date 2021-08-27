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
                12 64 6 \
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
            clear
            echo "Shutting down without changes ..."
            echo "Cut power when you see no status LED blinking anymore."
            exit 2
            ;;
        *)
            # 3 --> ESC/CANCEL = EXIT TO TERMINAL
            clear
            echo "Exit to Terminal from RaspiBlitz Setup ..."
            exit  3
esac