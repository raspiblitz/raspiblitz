#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)
NETclnEncryptedHSM="${netprefix}clnEncryptedHSM"

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE="C-lightning repair options for $CHAIN"
MENU=""
OPTIONS=()

if [ ${NETclnEncryptedHSM} = "off" ];then
    OPTIONS+=(ENCRYPT "Encrypt the hsm_secret")
elif [ ${NETclnEncryptedHSM} = "on" ];then
    OPTIONS+=(PASSWORD_C "Change the hsm_secret encryption password")
    OPTIONS+=(DECRYPT "Decrypt the hsm_secret")
fi
if [ ${NETclnEncryptedHSM} = "on" ];then
  if [ ! -f "/root/.${netprefix}cln.pw" ]; then
    OPTIONS+=(AUTOUNLOCK-ON "Auto-decrypt the hsm_secret after boot")
  else
    OPTIONS+=(AUTOUNLOCK-OFF "Do not auto-decrypt the hsm_secret after boot")
  fi
fi
    OPTIONS+=(BACKUP "Full backup (hsm_secret + lightningd.sqlite3")
    OPTIONS+=(RESET "Reset the wallet and create new")
    OPTIONS+=(FILERESTORE "Restore from a rescue file")
    OPTIONS+=(SEEDRESTORE "Restore from a seed (onchain funds only)")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in
  ENCRYPT)
  /home/admin/config.scripts/cln.hsmtool.sh encrypt
  source /mnt/hdd/raspiblitz.conf
  ;;

  DECRYPT)
  /home/admin/config.scripts/cln.hsmtool.sh decrypt
  source /mnt/hdd/raspiblitz.conf
  ;;
  
  PASSWORD_C)
  /home/admin/config.scripts/cln.hsmtool.sh change-password
  ;;
  
  AUTOUNLOCK-ON)
  /home/admin/config.scripts/cln.hsmtool.sh autounlock-on
  ;;
  
  AUTOUNLOCK-OFF)
  /home/admin/config.scripts/cln.hsmtool.sh autounlock-off
  ;;
  
  BACKUP)
  ## from dialogLightningWallet.sh 
  # run upload dialog and get result
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  /home/admin/config.scripts/cln.backup.sh cln-export-gui production $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null

  ;;
  RESET)
  # backup
  ## from dialogLightningWallet.sh 
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  /home/admin/config.scripts/cln.backup.sh cln-export-gui production $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null
  echo
  echo "The rescue file is stored on the SDcard named cln-rescue.*.tar.gz just in case."
  echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
  echo "Press ENTER to continue or CTRL+C to abort"
  read key
  # reset
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
  # new
  /home/admin/config.scripts/cln.hsmtool.sh new
  ;;
  
  FILERESTORE)
  # backup
  ## from dialogLightningWallet.sh 
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  /home/admin/config.scripts/cln.backup.sh cln-export-gui production $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null
  echo
  echo "The rescue file is stored on the SDcard named cln-rescue.*.tar.gz just in case."
  echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
  echo "Press ENTER to continue or CTRL+C to abort"
  read key
  # reset
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
  # import file
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  /home/admin/config.scripts/cln.backup.sh cln-import-gui production $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null
  ;;
  
  SEEDRESTORE)
  # backup
  ## from dialogLightningWallet.sh 
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  clear
  /home/admin/config.scripts/cln.backup.sh cln-export-gui production $_temp
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null
  echo
  echo "The rescue file is stored on the SDcard named cln-rescue.*.tar.gz just in case."
  echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
  echo "Press ENTER to continue or CTRL+C to abort"
  read key
  # reset
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/config
  sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
  # import seed
  _temp="/var/cache/raspiblitz/.temp.tmp"
  /home/admin/config.scripts/cln.backup.sh seed-import-gui $_temp
  /home/admin/config.scripts/cln.hsmtool.sh seed "$CHAIN" "$(cat $_temp)"
  source $_temp 2>/dev/null
  sudo rm $_temp 2>/dev/null
  # regenerate config
  /home/admin/config.scripts/cln.install.sh on $CHAIN
  ;;

esac

exit 0