#!/bin/bash
_temp="./download/dialog.$$"

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null

passwordValid=0
result=""
while [ ${passwordValid} -eq 0 ]
  do
    # show password info dialog
    dialog --backtitle "RaspiBlitz - Setup" --msgbox "RaspiBlitz uses 4 different passwords.
Referenced as password A, B, C and D.

A) Master User Password
B) Blockchain RPC Password
C) LND Wallet Password
D) LND Seed Password

Choose now 4 new passwords - all min 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 15 52

    # ask user for new password A
    dialog --backtitle "RaspiBlitz - Setup"\
       --inputbox "Please enter your Master/Admin Password A:\n!!! This is new password to login per SSH !!!" 10 52 2>$_temp

    # get user input
    result=$( cat $_temp )
    shred $_temp
    passwordValid=1

    clearedResult=$(echo "${result}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#result} ] || [ ${#clearedResult} -eq 0 ]; then
      clear
      echo "FAIL - Password contained not allowed chars (see next screen)"
      echo "Press ENTER to continue .."
      read key
      passwordValid=0
    else

      # change user passwords and then change hostname
      echo "pi:$result" | sudo chpasswd
      echo "root:$result" | sudo chpasswd
      echo "bitcoin:$result" | sudo chpasswd
      echo "admin:$result" | sudo chpasswd
      sleep 1

      # sucess info dialog
      dialog --backtitle "RaspiBlitz" --msgbox "OK - password changed to '$result'\nfor all users pi, admin, root & bitcoin" 6 52

      # repeat until user input is nit length 0
      result=""
      dialog --backtitle "RaspiBlitz - Setup"\
      --inputbox "Enter your RPC Password B:" 9 52 2>$_temp
      result=$( cat $_temp )
      shred $_temp

      clearedResult=$(echo "${result}" | tr -dc '[:alnum:]-.' | tr -d ' ')
      if [ ${#clearedResult} != ${#result} ] || [ ${#clearedResult} -eq 0 ]; then
        clear
        echo "FAIL - Password contained not allowed chars (see next screen)"
        echo "Press ENTER to continue to start again"
        read key
        passwordValid=0
      else

        # set Blockchain RPC Password (for admin cli & template for user bitcoin)
        sed -i "s/^rpcpassword=.*/rpcpassword=${result}/g" /home/admin/assets/${network}.conf
        sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${result}/g" /home/admin/assets/lnd.${network}.conf

        # success info dialog
        dialog --backtitle "RaspiBlitz - SetUP" --msgbox "OK - RPC password changed to '$result'\n\nNow starting the Setup of your RaspiBlitz." 7 52
        clear
  
      fi

    fi

  done



