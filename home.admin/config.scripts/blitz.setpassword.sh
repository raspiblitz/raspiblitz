#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a passwords A,B,C & D"
 echo "blitz.setpassword.sh [?a|b|c|d] [?newpassword] "
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit
fi

# load raspiblitz config (if available)
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# 1. parameter [?a|b|c|d]
abcd=$1

# 2. parameter [?newpassword]
newPassword=$2

# run interactive if no further parameters
OPTIONS=()
if [ ${#abcd} -eq 0 ]; then
    OPTIONS+=(A "Master User Password / SSH")
    OPTIONS+=(B "RPC Password (blockchain/lnd)")
    OPTIONS+=(C "LND Wallet Password")
    OPTIONS+=(D "LND Seed Password")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz" \
                --title "Set Password" \
                --menu "Which password to change?" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        A)
          abcd='a';
          ;;
        B)
          abcd='b';
          ;;
        C)
          abcd='c';
          ;;
        D)
          abcd='d';
          ;;
    esac
fi

echo "Changing Password ${abcd} ..."
echo ""

# PASSWORD A
if [ "${abcd}" = "a" ]; then

  echo "TODO: Password A"

# PASSWORD B
elif [ "${abcd}" = "b" ]; then

  echo "TODO: Password B"

# PASSWORD C
elif [ "${abcd}" = "c" ]; then

  clear
  echo ""
  echo "****************************************************************************"
  echo "Change LND Wallet Password --> lncli changepassword"
  echo "****************************************************************************"
  echo "This is your Password C on the RaspiBlitz to unlock your LND wallet."
  echo "If you had Auto-Unlock active - you need to re-activate after this."
  echo "To CANCEL use CTRL+C"
  echo "****************************************************************************"

  # let LND-CLI handle the password change
  result=$(lncli changepassword)
  echo "result(${result})"

  # deactivate AUTO-UNLOCK if activated
  sudo /home/admin/config.scripts/lnd.autounlock.sh off

# PASSWORD D
elif [ "${abcd}" = "d" ]; then

  echo "#### NOTICE ####"
  echo "Sorry - the password D cannot be changed. Its the password you set on creating your wallet to protect your seed (the list of words)."

# everything else
else
  echo "FAIL: there is no password '${abcd}' (reminder: use lower case)"
fi

echo ""