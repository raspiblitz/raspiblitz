#!/bin/bash
_temp="./download/dialog.$$"

## get basic info
source /mnt/hdd/raspiblitz.conf 

passwordValid=0
result=""
while [ ${passwordValid} -eq 0 ]
  do
    # show password info dialog
    dialog --backtitle "RaspiBlitz - Recover Setup" --msgbox "Your previous RaspiBlitz config was recovered.

You need to set a new Password A:
A) Master User Password

Passwords B, C & D stay as before.

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 14 52

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

      # activate lnd & bitcoin service
      echo "Enabling Services"
      sudo systemctl daemon-reload
      sudo systemctl enable lnd.service
      sudo systemctl enable ${network}d.service
      if [ "${rtlWebinterface}" = "on" ]; then
        sudo systemctl enable RTL
      fi

      # remove flag that freshly recovered
      sudo rm /home/admin/raspiblitz.recover.info

      # when auto-unlock is activated then Password C is needed to be restored on SD card
      if [ "${autoUnlock}" = "on" ]; then

        # reset auto-unlock feature
        dialog --backtitle "RaspiBlitz - Setup" --msgbox "You had the Auto-Unlock feature enabled.

In the next dialog you need to re-enter your
ACTUAL/OLD Password C to re-activate the
Auto-Unlock feature. Enter a empty password
to deactivate the Auto-Unlock feature.
" 10 52
        sudo /home/admin/config.scripts/lnd.autounlock.sh on
        dialog --backtitle "RaspiBlitz" --msgbox "FINAL REBOOT IS NEEDED." 6 52

      else
        dialog --backtitle "RaspiBlitz" --msgbox "New SSH password A is '$result'\nFINAL REBOOT IS NEEDED." 6 52
      fi

      sudo shutdown -r now
    fi

  done

  



