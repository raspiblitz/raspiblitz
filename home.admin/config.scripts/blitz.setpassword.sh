#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a passwords A,B,C & D"
 echo "blitz.setpassword.sh [?a|b|c|d] [?newpassword]"
 exit 1
fi

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
                --backtitle "Set Password" \
                --title "Which password to change?" \
                --menu "Choose Password" \
                8 50 4 \
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

echo "Changing  '${abcd}' ..."
