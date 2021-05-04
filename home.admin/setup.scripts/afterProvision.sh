#!/bin/bash

# this is more a todo list of things that got removed from oter parts of the old setup/login and need to find a new place/home


############# SCB activation

  # check if there is a channel.backup to activate
  gotSCB=$(ls /home/admin/channel.backup 2>/dev/null | grep -c 'channel.backup')
  if [ ${gotSCB} -eq 1 ]; then

    echo "*** channel.backup Recovery ***"
    lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup 2>/home/admin/.error.tmp
    error=`cat /home/admin/.error.tmp`
    rm /home/admin/.error.tmp 2>/dev/null

    if [ ${#error} -gt 0 ]; then

      # output error message
      echo ""
      echo "!!! FAIL !!! SOMETHING WENT WRONG:"
      echo "${error}"

      # check if its possible to give background info on the error
      notMachtingSeed=$(echo $error | grep -c 'unable to unpack chan backup')
      if [ ${notMachtingSeed} -gt 0 ]; then
        echo "--> ERROR BACKGROUND:"
        echo "The WORD SEED is not matching the channel.backup file."
        echo "Either there was an error in the word seed list or"
        echo "or the channel.backup file is from another RaspiBlitz."
        echo 
      fi

      # basic info on error
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo 
      echo "You can try after full setup to restore channel.backup file again with:"
      echo "lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup"
      echo
      echo "Press ENTER to continue for now ..."
      read key
    else
      mv /home/admin/channel.backup /home/admin/channel.backup.done
      dialog --title " OK channel.backup IMPORT " --msgbox "
LND accepted the channel.backup file you uploaded. 
It will now take around a hour until you can see,
if LND was able to recover funds from your channels.
     " 9 56
    fi
  
  fi