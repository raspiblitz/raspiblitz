#!/bin/bash
_temp=$(mktemp -p /dev/shm/)

## get basic info
source /home/admin/raspiblitz.info

# choose blockchain or select migration
OPTIONS=()
OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning (DEFAULT)")
OPTIONS+=(LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)")
OPTIONS+=(MIGRATION "Upload a Migration File from old RaspiBlitz")
CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz ${codeVersion} - Setup" \
                --title "⚡ Welcome to your RaspiBlitz ⚡" \
                --menu "\nChoose how you want to setup your RaspiBlitz: \n " \
                12 64 6 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
clear
network=""
case $CHOICE in
        CLOSE)
            # TODO: check if case every comes up
            echo "CLOSE"
            exit 1;
            ;;
        BITCOIN)
            network="bitcoin"
            ;;
        LITECOIN)
            network="litecoin"
            ;;
        MIGRATION)
            # send over to the migration dialogs
            /home/admin/00migrationDialog.sh raspiblitz
            exit 0
            ;;
esac

# on cancel - exit to terminal
if [ "${network}" == "" ]; then
  echo "# exit to terminal"
  exit 1
fi

# prepare the config file (what will later become the raspiblitz.config)
source /home/admin/_version.info
CONFIGFILE="/home/admin/raspiblitz.config.tmp"
rm $CONFIGFILE 2>/dev/null
echo "# RASPIBLITZ CONFIG FILE" > $CONFIGFILE
echo "raspiBlitzVersion='${codeVersion}'" >> $CONFIGFILE
echo "lcdrotate=1" >> $CONFIGFILE
echo "network=${network}" >> $CONFIGFILE
echo "chain=main" >> $CONFIGFILE

# prepare the setup file (that constains info just needed for the rest of setup process)
SETUPFILE="/home/admin/raspiblitz.setup.tmp"
rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP FILE" > $SETUPFILE

###################
# ENTER NAME
###################

# welcome and ask for name of RaspiBlitz
result=""
while [ ${#result} -eq 0 ]
  do
    l1="Please enter the name of your new RaspiBlitz:\n"
    l2="one word, keep characters basic & not too long"
    dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --inputbox "$l1$l2" 11 52 2>$_temp
    result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
    shred -u $_temp
    echo "processing ..."
    sleep 3
  done

# set lightning alias
sed -i "s/^alias=.*/alias=${result}/g" /home/admin/assets/lnd.${network}.conf

# store hostname for later - to be set right before the next reboot
# work around - because without a reboot the hostname seems not updates in the whole system
valueExistsInInfoFile=$(sudo cat /home/admin/raspiblitz.info | grep -c "hostname=")
if [ ${valueExistsInInfoFile} -eq 0 ]; then
  # add
  echo "hostname=${result}" >> /home/admin/raspiblitz.info
else
  # update
  sed -i "s/^hostname=.*/hostname=${result}/g" /home/admin/raspiblitz.info
fi

###################
# ENTER PASSWORDS 
###################

# show password info dialog
dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --msgbox "RaspiBlitz uses 4 different passwords.
Referenced as password A, B, C and D.

A) Master User Password
B) Blockchain RPC Password
C) LND Wallet Password
D) LND Seed Password

Choose now 4 new passwords - all min 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 15 52

# call set password a script
sudo /home/admin/config.scripts/blitz.setpassword.sh a

# sucess info dialog
dialog --backtitle "RaspiBlitz" --msgbox "OK - password A was set\nfor all users pi, admin, root & bitcoin" 6 52

# call set password b script
sudo /home/admin/config.scripts/blitz.setpassword.sh b

# success info dialog
dialog --backtitle "RaspiBlitz" --msgbox "OK - RPC password changed \n\nNow starting the Setup of your RaspiBlitz." 7 52

###################
# TOR BY DEFAULT 
# https://github.com/rootzoll/raspiblitz/issues/592
# 
###################
echo "runBehindTor=on" >> /home/admin/raspiblitz.info
#whiptail --title ' Privacy Level - How do you want to run your node? ' --yes-button='Public IP' --no-button='TOR NETWORK' --yesno "Running your Lightning node with your Public IP is common and faster, but might reveal your personal identity and location.\n
#You can better protect your privacy with running your lightning node as a TOR Hidden Service from the start, but it can make it harder to connect with other non-TOR nodes and remote mobile apps later on.
#  " 12 75
#if [ $? -eq 1 ]; then
#  echo "runBehindTor=on" >> /home/admin/raspiblitz.info
#fi

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=20/g" /home/admin/raspiblitz.info

clear