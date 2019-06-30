#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

# only show warning when bitcoin
if [ "$network" = "bitcoin" ]; then

  # detect hardware version of RaspberryPi
  # https://www.unixtutorial.org/command-to-confirm-raspberry-pi-model
  raspberryPi=$(cat /proc/device-tree/model | cut -d " " -f 3 | sed 's/[^0-9]*//g')
  if [ ${#raspberryPi} -eq 0 ]; then
    raspberryPi=0
  fi
  echo "RaspberryPi Model Version: ${raspberryPi}"
  if [ ${raspberryPi} -lt 4 ]; then
    # raspberryPi 3 and lower
    msg=" This old RaspberryPi has very limited CPU power.\n"
    msg="$msg To sync & validate the complete blockchain\n"
    msg="$msg can take multiple days - even weeksn"
    msg="$msg Its recommended to use another option.\n"
    msg="$msg \n"
    msg="$msg So do you really want start syncing now?"
  else
    # raspberryPi 4 and up
    msg=" Your RaspiBlitz will sync and validate\n"
    msg="$msg the complete blockchain by itself.\n"
    msg="$msg This can take multiple days, but\n"
    msg="$msg its the best to do it this way.\n"
    msg="$msg \n"
    msg="$msg So do you want start syncing now?"
  fi
  
  dialog --title " WARNING " --yesno "${msg}" 11 57
  response=$?
  case $response in
     0) echo "--> OK";;
     1) exit 1;;
     255) exit 1;;
  esac

  clear
  if [ ${raspberryPi} -lt 4 ]; then
    echo "********************************"
    echo "This is madness. This is Sparta!"
    echo "********************************"
    echo ""
    sleep 3
  else
    echo "**********************************"
    echo "Dont Trust, verify - starting sync"
    echo "**********************************"
    echo ""
    sleep 3
  fi

fi  

echo "*** Activating Blockain Sync ***"

sudo mkdir /mnt/hdd/${network} 2>/dev/null
sudo /home/admin/XXcleanHDD.sh -blockchain -force

# set so that 10raspiblitz.sh has a flag to see that resync is running
sudo sed -i "s/^state=.*/state=resync/g" /home/admin/raspiblitz.info

echo "OK - sync is activated"

if [ "${setupStep}" = "100" ]; then

  # start servives
  sudo systemctl start bitcoind
  sudo systemctl start lnd

else

  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info

  # continue setup
  ./60finishHDD.sh

fi
