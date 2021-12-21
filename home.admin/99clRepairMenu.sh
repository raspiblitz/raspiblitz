#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

NETclEncryptedHSM="${netprefix}clEncryptedHSM"

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE="C-lightning repair options for $CHAIN"
MENU=""
OPTIONS=()

if [ "$(eval echo \$${netprefix}clEncryptedHSM)" = "off" ];then
    OPTIONS+=(ENCRYPT "Encrypt the hsm_secret")
elif [ "$(eval echo \$${netprefix}clEncryptedHSM)"  = "on" ];then
    OPTIONS+=(PASSWORD_C "Change the hsm_secret encryption password")
    OPTIONS+=(DECRYPT "Decrypt the hsm_secret")
  if [ ! -f "/home/bitcoin/.${netprefix}cl.pw" ]; then
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
    /home/admin/config.scripts/cl.hsmtool.sh encrypt $CHAIN
    source /mnt/hdd/raspiblitz.conf
    ;;

  DECRYPT)
    /home/admin/config.scripts/cl.hsmtool.sh decrypt $CHAIN
    source /mnt/hdd/raspiblitz.conf
    ;;
  
  PASSWORD_C)
    /home/admin/config.scripts/cl.hsmtool.sh change-password $CHAIN
    ;;
  
  AUTOUNLOCK-ON)
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-on $CHAIN
    ;;
  
  AUTOUNLOCK-OFF)
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-off $CHAIN
    ;;
  
  BACKUP)
    ## from dialogLightningWallet.sh 
    # run upload dialog and get result
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    clear
    /home/admin/config.scripts/cl.backup.sh cl-export-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    echo
    echo "Press ENTER when finished downloading."
    read key
    ;;
  
  RESET)
    # backup
    ## from dialogLightningWallet.sh 
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    clear
    /home/admin/config.scripts/cl.backup.sh cl-export-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    echo
    echo "The rescue file is stored on the SDcard named cl-rescue.*.tar.gz just in case."
    echo
    echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    # reset
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
    # make sure the new hsm_secret is treated as unencrypted and clear autounlock
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clEncryptedHSM "off"
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clAutoUnlock "off"
    # new
    /home/admin/config.scripts/cl.hsmtool.sh new $CHAIN
    # set the lightningd service file on each active network
    if [ "${cl}" == "on" ] || [ "${cl}" == "1" ]; then
      /home/admin/config.scripts/cl.install-service.sh mainnet
    fi
    if [ "${tcl}" == "on" ] || [ "${tcl}" == "1" ]; then
      /home/admin/config.scripts/cl.install-service.sh testnet
    fi
    if [ "${scl}" == "on" ] || [ "${scl}" == "1" ]; then
      /home/admin/config.scripts/cl.install-service.sh signet
    fi
    ;;
  
  FILERESTORE)
    # backup
    ## from dialogLightningWallet.sh 
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    clear
    /home/admin/config.scripts/cl.backup.sh cl-export-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    echo
    echo "The rescue file is stored on the SDcard named cl-rescue.*.tar.gz just in case."
    echo
    echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    # reset
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
    # import file
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    clear
    /home/admin/config.scripts/cl.backup.sh cl-import-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    ;;
  
  SEEDRESTORE)
    # backup
    ## from dialogLightningWallet.sh 
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    clear
    /home/admin/config.scripts/cl.backup.sh cl-export-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    echo
    echo "The rescue file is stored on the SDcard named cl-rescue.*.tar.gz just in case."
    echo
    echo "The next step will overwrite the old C-lighthning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    # reset
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/config
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/*.*
    # import seed
    _temp="/var/cache/raspiblitz/.temp.tmp"
    /home/admin/config.scripts/cl.backup.sh seed-import-gui $_temp
    source $_temp
    /home/admin/config.scripts/cl.hsmtool.sh seed-force "$CHAIN" "${seedWords}"
    sudo rm $_temp 2>/dev/null
    # regenerate config
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-off
    /home/admin/config.scripts/cl.hsmtool.sh decrypt
    /home/admin/config.scripts/cl.install.sh on $CHAIN
    ;;

esac

exit 0