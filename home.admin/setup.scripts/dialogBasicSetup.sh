#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source $SETUPFILE

# choose blockchain or select migration
OPTIONS=()
OPTIONS+=(BITCOIN1 "Setup BITCOIN & Lightning Network Daemon (LND)")
OPTIONS+=(BITCOIN2 "Setup BITCOIN & c-lightning by blockstream")
OPTIONS+=(LITECOIN "Setup LITECOIN & Lightning Network Daemon (LND)")
OPTIONS+=(MIGRATION "Upload a Migration File from old RaspiBlitz")
CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz ${codeVersion} - Setup" \
                --title "⚡ Welcome to your RaspiBlitz ⚡" \
                --menu "\nChoose how you want to setup your RaspiBlitz: \n " \
                13 64 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
clear
network=""
lightning=""
migrationOS=""
case $CHOICE in
        BITCOIN1)
            network="bitcoin"
            lightning="lnd"
            ;;
        BITCOIN2)
            network="bitcoin"
            lightning="cln"
            ;;
        LITECOIN)
            network="litecoin"
            lightning="lnd"
            ;;
        MIGRATION)
            migrationOS="raspiblitz"
            ;;
esac

# on cancel - exit with 1
if [ "${network}" == "" ] && [ "${migrationOS}" == "" ]; then
  exit 1
fi

# write results to setup sate
echo "migrationOS='${migrationOS}'" >> $SETUPFILE
echo "migrationVersion=''" >> $SETUPFILE
echo "lightning=${lightning}" >> $SETUPFILE
echo "network=${network}" >> $SETUPFILE

exit 0