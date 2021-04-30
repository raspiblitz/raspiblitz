#!/bin/bash
_temp=$(mktemp -p /dev/shm/)

## get basic info
source /home/admin/raspiblitz.info

# set place where zipped TAR file gets stored on migration dialog
defaultZipPath="/mnt/hdd/temp"

# prepare the config file (what will later become the raspiblitz.config)
source /home/admin/_version.info
CONFIGFILE="/home/admin/raspiblitz.config.tmp"
rm $CONFIGFILE 2>/dev/null
echo "# RASPIBLITZ CONFIG FILE" > $CONFIGFILE
echo "raspiBlitzVersion='${codeVersion}'" >> $CONFIGFILE
echo "lcdrotate=1" >> $CONFIGFILE

# prepare the setup file (that constains info just needed for the rest of setup process)
SETUPFILE="/home/admin/raspiblitz.setup.tmp"
rm $SETUPFILE 2>/dev/null
echo "# RASPIBLITZ SETUP FILE" > $SETUPFILE

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
migration=""
case $CHOICE in
        CLOSE)
            # TODO: check if case every comes up
            echo "CLOSE"
            exit 1;
            ;;
        BITCOIN)
            network="bitcoin"
            echo "network=bitcoin" >> $CONFIGFILE
            ;;
        LITECOIN)
            network="litecoin"
            echo "network=litecoin" >> $CONFIGFILE
            ;;
        MIGRATION)
            migration="raspiblitz"
            echo "migration=raspiblitz" >> $SETUPFILE
            ;;
esac

# IMPORT MIGRATION DIALOG
# if fails then restart the complete provision dialog
if [ "${migration}" == "raspiblitz" ]; then

  # make sure that temp directory exists and can be written by admin
  sudo mkdir -p ${defaultZipPath}
  sudo chmod 777 -R ${defaultZipPath}

  clear
  echo
  echo "*****************************"
  echo "* UPLOAD THE MIGRATION FILE *"
  echo "*****************************"
  echo "If you have a migration file on your laptop you can now"
  echo "upload it and restore on the new HDD/SSD."
  echo
  echo "ON YOUR LAPTOP open a new terminal and change into"
  echo "the directory where your migration file is and"
  echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
  echo "scp -r ./raspiblitz-*.tar.gz admin@${localip}:${defaultZipPath}"
  echo ""
  echo "Use password 'raspiblitz' to authenticate file transfer."
  echo "PRESS ENTER when upload is done."
  read key

  countZips=$(sudo ls ${defaultZipPath}/raspiblitz-*.tar.gz 2>/dev/null | grep -c 'raspiblitz-')

  # in case no upload found
  if [ ${countZips} -eq 0 ]; then
    echo
    echo "FAIL: Was not able to detect uploaded file in ${defaultZipPath}"
    echo "error='no file found'"
    sleep 3
    /home/admin/00provisionDialog.sh
    exit 1
  fi

  # in case of multiple files
  if [ ${countZips} -gt 1 ]; then
    echo
    echo "# FAIL: Multiple possible files detected in ${defaultZipPath}"
    echo "error='multiple files'"
    sleep 3
    /home/admin/00provisionDialog.sh
    exit 1
  fi

  # unzip migration file and check
  echo
  echo "OK: Upload found in ${defaultZipPath} - restoring data ... (please wait)"
  source <(sudo /home/admin/config.scripts/blitz.migration.sh "import")
  if [ ${#error} -gt 0 ]; then
    echo
    echo "# FAIL: Was not able to restore data"
    echo "error='${error}'"
    sleep 3
    /home/admin/00provisionDialog.sh
    exit 1
  fi
  
  echo
  echo "OK: Migration data was imported - will now recover/restore RaspiBlitz with this data"
  echo "PRESS ENTER TO CONTINUE"
  read key
  exit 0
fi


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