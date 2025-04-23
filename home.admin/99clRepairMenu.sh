#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/app-data/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

sudo mkdir /var/cache/raspiblitz/temp 2>/dev/null


function clRescan() {
  trap 'rm -f "$_temp"' EXIT
  _temp=$(mktemp -p /dev/shm/)
  dialog --backtitle "Choose the new gap limit" \
  --title "Enter the rescan depth or blockheight (-)" \
  --inputbox "
Enter the number of blocks to rescan from the current tip
or use a negative number for the absolute blockheight to scan from.

If left empty will start to rescan from the block 700000 (-700000).
" 12 71 2> "$_temp"
  BLOCK=$(cat "$_temp")
  if [ ${#BLOCK} -eq 0 ]; then
    BLOCK="-700000"
  fi
  sudo /home/admin/config.scripts/cl.backup.sh "${CHAIN}" recoverymode on "${BLOCK}"
  sudo systemctl restart ${netprefix}lightningd
}

function resetWallet() {
    echo "# Delete ${CLCONF}"
    sudo rm -f ${CLCONF}
    echo "# Delete and recreate /home/bitcoin/.lightning/${CLNETWORK}"
    sudo rm -rf /home/bitcoin/.lightning/${CLNETWORK}
    sudo -u bitcoin mkdir /home/bitcoin/.lightning/${CLNETWORK}
}

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE="Core Lightning repair options for $CHAIN"
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
    OPTIONS+=(BACKUP "Full backup (hsm_secret + lightningd.sqlite3)")
    OPTIONS+=(RESET "Reset the wallet and create new")
    OPTIONS+=(FILERESTORE "Restore from a rescue file")
    OPTIONS+=(SEEDRESTORE "Restore from a seed (onchain funds only)")
    OPTIONS+=(RESCAN "Rescan for onchain funds from a given block")

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
    sudo /home/admin/config.scripts/cl.hsmtool.sh encrypt $CHAIN
    source /mnt/hdd/app-data/raspiblitz.conf
    ;;

  DECRYPT)
    /home/admin/config.scripts/cl.hsmtool.sh decrypt $CHAIN
    source /mnt/hdd/app-data/raspiblitz.conf
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
    if [ "${cl}" == "on" ] || [ "${cl}" == "1" ] && [ "${clEncryptedHSM}" != "on" ]; then
      dialog \
       --title "Encrypt the Core Lightning wallet" \
       --msgbox "
Will proceed to encrypt and lock the Core Lightning wallet to prevent it from starting automatically after the backup.
Save this password as it will be needed to restore the backup (same as the Password C for CLN)." 10 55
      sudo /home/admin/config.scripts/cl.hsmtool.sh encrypt mainnet
    fi
    if [ "${clAutoUnlock}" = "on" ]; then
      /home/admin/config.scripts/cl.hsmtool.sh autounlock-off mainnet
    fi
    /home/admin/config.scripts/cl.hsmtool.sh lock mainnet
    ## from dialogLightningWallet.sh
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
    echo "The next step will overwrite the old Core Lightning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key

    resetWallet

    # make sure the new hsm_secret is treated as unencrypted and clear autounlock
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clEncryptedHSM "off"
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clAutoUnlock "off"
    # new
    /home/admin/config.scripts/cl.hsmtool.sh new $CHAIN
    # create config
    /home/admin/config.scripts/cl.install.sh on $CHAIN
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
    echo "The next step will overwrite the old Core Lightning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key

    resetWallet

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
    echo "The next step will overwrite the old Core Lightning $CHAIN wallet"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key

    resetWallet

    # import seed
    _temp="/var/cache/raspiblitz/.temp.tmp"
    /home/admin/config.scripts/cl.backup.sh seed-import-gui $_temp
    source $_temp
    /home/admin/config.scripts/cl.hsmtool.sh seed-force "$CHAIN" "${seedWords}"
    sudo rm $_temp 2>/dev/null
    if ! sudo ls /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret 2>/dev/null; then
      echo "# There was no hsm_secret created - exiting"
      exit 15
    fi
    # regenerate config
    /home/admin/config.scripts/cl.hsmtool.sh autounlock-off
    /home/admin/config.scripts/cl.hsmtool.sh decrypt
    /home/admin/config.scripts/cl.install.sh on $CHAIN

    clRescan
    ;;

  RESCAN)
    clRescan
    ;;
esac

exit 0