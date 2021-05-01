#!/bin/bash

# get basic info
source /home/admin/raspiblitz.info

# temp file for dialog results
_temp=$(mktemp -p /dev/shm/)

# flags of what passwords are to set by user
setPasswordA=1
setPasswordB=1
setPasswordC=1

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
            # send over to the migration dialogs
            /home/admin/00migrationDialog.sh raspiblitz
            exit 0
            ;;
esac

# on cancel - exit to terminal
if [ "${network}" == "" ]; then
  echo "# you selected cancel - exited to terminal"
  echo "# use command 'restart' to reboot & start again"
  exit 1
fi

# prepare the config file (what will later become the raspiblitz.config)
source /home/admin/_version.info
CONFIGFILE="/home/admin/raspiblitz.config.tmp"
rm $CONFIGFILE 2>/dev/null
echo "# RASPIBLITZ CONFIG FILE" > $CONFIGFILE
echo "raspiBlitzVersion='${codeVersion}'" >> $CONFIGFILE
echo "lcdrotate=1" >> $CONFIGFILE
echo "lightning=${lightning}" >> $CONFIGFILE
echo "network=${network}" >> $CONFIGFILE
echo "chain=main" >> $CONFIGFILE
echo "runBehindTor=on" >> $CONFIGFILE

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
echo "hostname=${result}" >> $CONFIGFILE

###################
# DECIDE LIGHTNING
# do this before passwords, because password C not needed if LND rescue file is uploaded
###################

# flags for sub dialogs after choice
uploadLNDRESCUE=0
enterSEED=0
uploadSCB=0

OPTIONS=()
OPTIONS+=(NEW "Setup a brand new Lightning Node (DEFAULT)")
OPTIONS+=(OLD "I had an old Node I want to recover/restore")
CHOICE=$(dialog --backtitle "RaspiBlitz" --clear --title "LND Setup" --menu "LND Data & Wallet" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

if [ "${CHOICE}" == "NEW" ]; then

  # mark all passwords to be set at the end
  setPasswordA=1
  setPasswordB=1
  setPasswordC=1

elif [ "${CHOICE}" == "OLD" ]; then

  # get more details what kind of old lightning wallet user has
  OPTIONS=()
  OPTIONS+=(LNDRESCUE "LND tar.gz-Backupfile (BEST)")
  OPTIONS+=(SEED+SCB "Seed & channel.backup file (OK)")
  OPTIONS+=(ONLYSEED "Only Seed Word List (FALLBACK)")
  CHOICE=$(dialog --backtitle "RaspiBlitz" --clear --title "RECOVER LND DATA & WALLET" --menu "Data you have to recover from?" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  if [ "${CHOICE}" == "LNDRESCUE" ]; then

    # just activate LND rescue upload
    uploadLNDRESCUE=1

    # dont set password c anymore later on
    setPasswordC=0

  elif [ "${CHOICE}" == "SEED+SCB" ]; then

    # activate SEED input & SCB upload
    enterSEED=1
    uploadSCB=1

  elif [ "${CHOICE}" == "ONLYSEED" ]; then

    # activate SEED input & SCB upload
    enterSEED=1

  else
    echo "# you selected cancel - exited to terminal"
    echo "# use command 'restart' to reboot & start again"
    exit 1
  fi

else
  echo "# you selected cancel - exited to terminal"
  echo "# use command 'restart' to reboot & start again"
  exit 1
fi

# UPLOAD LND RESCUE FILE dialog (if activated by dialogs above)
if [ ${uploadLNDRESCUE} -eq 1 ]; then
  echo "TODO: UPLOAD LND RESCUE FILE"
  exit 1
fi


# INPUT LIGHTNING SEED dialog (if activated by dialogs above)
if [ ${enterSEED} -eq 1 ]; then
  echo "TODO: INPUT LIGHTNING SEED"
  exit 1
fi

# UPLOAD STATIC CHANNEL BACKUP FILE dialog (if activated by dialogs above)
if [ ${uploadSCB} -eq 1 ]; then
  echo "TODO: UPLOAD STATIC CHANNEL BACKUP FILE"
  exit 1
fi

###################
# ENTER PASSWORDS ---> combine with migration dialog to reduce code duplication
###################

# show password info dialog
dialog --backtitle "RaspiBlitz - Setup" --msgbox "RaspiBlitz uses 3 different passwords.
Referenced as password A, B & C.

PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (RPC & Additional Apps)
PASSWORD C) Lightning Wallet Password for Unlock

Set now the 3 passwords - all min 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 15 54

clear
sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD A - Main User Password" $_temp
password=$(sudo cat $_temp)
echo "passwordA='${password}'" >> $SETUPFILE
dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password A set" 7 20

clear
sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD B - APP Password" $_temp
password=$(sudo cat $_temp)
echo "passwordB='${password}'" >> $SETUPFILE
dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password B set" 7 20

clear
sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD C - Lightning Wallet Password" $_temp
password=$(sudo cat $_temp)
echo "passwordC='${password}'" >> $SETUPFILE
dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password C set" 7 20

echo "TODO: continue with further "
exit 1

clear