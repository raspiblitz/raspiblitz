#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/run/raspiblitz-setup/raspiblitz.setup"
source $SETUPFILE

####################################################
# INPUT PASSWORDS (based on flags from raspiblitz.setup)

# dynamic info string on what passwords need to be changed
# at the moment its always
passwordinfo="A"
echo "A"
if [ "${setPasswordB}" == "1" ]; then
  passwordinfo="${passwordinfo}, B"
  echo "A1"
fi
if [ "${setPasswordC}" == "1" ]; then
  passwordinfo="${passwordinfo}, C"
fi

# if passwords are set in a migration situation, use different info text
if [ "${migrationOS}" == "" ]; then

  # info text on normal setup
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "RaspiBlitz uses 3 different passwords.
Referenced as password A, B & C.

PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (Additional Apps & API)
PASSWORD C) Lightning Wallet Password for Unlock

You will need to set now Password: ${passwordinfo}

Follow Password Rule: Minimum of 8 characters,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 16 54

else

  # info text on migration setup
  dialog --backtitle "RaspiBlitz - Migration Setup" --msgbox "You will need to set new passwords.

RaspiBlitz works with 3 different passwords:
PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (Additional Apps & API)
PASSWORD C) Lightning Wallet Password for Unlock

You will need to set now Password: ${passwordinfo}
(other passwords might stay like on your old node)

Follow Password Rules: Minimum of 8 characters,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 17 64

fi

# temp file for password results
passwordDir=$(mktemp -d "${SETUPFILE%/*}/.password.XXXXXXXX") || exit 1
_temp="$passwordDir/input"
trap 'rm -f -- "$_temp"; rmdir -- "$passwordDir"' EXIT

# Replace the complete handoff in the same directory. Keep the previous record if
# writing the new one fails; the admin menu must still own and read the result.
save_password() (
  key=$1
  record="$key='${password}'"
  [ -f "$SETUPFILE" ] && [ ! -L "$SETUPFILE" ] || return 1
  staged=$(mktemp "${SETUPFILE%/*}/.setup.XXXXXXXX") || return 1
  trap 'rm -f -- "$staged"' EXIT
  sed "/^${key}=/d" "$SETUPFILE" > "$staged" &&
    printf '%s\n' "$record" >> "$staged" &&
    chown --reference="$SETUPFILE" -- "$staged" &&
    chmod 640 -- "$staged" &&
    mv -fT -- "$staged" "$SETUPFILE" &&
    [ "$(tail -n 1 -- "$SETUPFILE")" = "$record" ]
)

confirm_saved() {
  until save_password "password$1"; do
    dialog --backtitle "RaspiBlitz - Setup" --yes-label "Retry" --no-label "Stop setup" \
      --yesno "Could not save Password $1. Check that setup storage is writable, then retry." 8 55 || return 1
  done
}

# PASSWORD A
if [ "${setPasswordA}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.passwords.sh set x "PASSWORD A - Main User Password" "$_temp" || exit 1
  password=$(cat -- "$_temp") || exit 1
  : > "$_temp" || exit 1
  if [ "${password}" == "" ]; then
    echo "FAIL password A cannot be empty - stopped setup"
    exit 1
  fi
  confirm_saved A || exit 1
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\nThanks - Password A accepted.\n\nUse this password for future SSH or Web-Admin logins to your RaspiBlitz & for sudo commands." 11 35
fi

# PASSWORD B
if [ "${setPasswordB}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.passwords.sh set x "PASSWORD B - APP Password" "$_temp" || exit 1
  password=$(cat -- "$_temp") || exit 1
  : > "$_temp" || exit 1
  if [ "${password}" == "" ]; then
    echo "FAIL password B cannot be empty - stopped setup"
    exit 1
  fi
  confirm_saved B || exit 1
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\nThanks - Password B accepted.\n\nUse this password as login for\nadditional Apps & API access." 10 34
fi

# PASSWORD C
if [ "${setPasswordC}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.passwords.sh set x "PASSWORD C - Lightning Wallet Password" "$_temp" || exit 1
  password=$(cat -- "$_temp") || exit 1
  : > "$_temp" || exit 1
  if [ "${password}" == "" ]; then
    echo "FAIL password C cannot be empty - stopped setup"
    exit 1
  fi
  confirm_saved C || exit 1
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\nThanks - Password C accepted.\n\nAlways use this password to \nunlock your Lightning Wallet." 10 34
fi

# debug info
clear
echo "# data from dialogs stored in to be further processed:"
echo "${SETUPFILE}"
exit 0
