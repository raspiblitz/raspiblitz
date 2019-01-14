#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a passwords A,B,C & D"
 echo "blitz.setpassword.sh [?a|b|c|d] [?newpassword] "
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

  echo "TODO: Password C"

# PASSWORD D
elif [ "${abcd}" = "d" ]; then

  echo "#### NOTICE ####"
  echo "Sorry - the password D cannot be changed. Its the password you set on creating your wallet to protect your seed (the list of words)."

# everything else
else
  echo "FAIL: there is no password '${abcd}' (reminder: use lower case)"
fi

echo ""