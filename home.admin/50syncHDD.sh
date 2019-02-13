#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

# only show warning when bitcoin
if [ "$network" = "bitcoin" ]; then
  msg=" The RaspberryPi has very limited CPU power.\n"
  msg="$msg To sync & validate the complete blockchain\n"
  msg="$msg can take multiple days - even weeks!\n"
  msg="$msg Its recommended to use another option.\n"
  msg="$msg \n"
  msg="$msg So do you really want start syncing now?"
  
  dialog --title " WARNING " --yesno "${msg}" 11 57
  response=$?
  case $response in
     0) echo "--> OK";;
     1) ./10setupBlitz.sh; exit 1;;
     255) ./10setupBlitz.sh; exit 1;;
  esac

  clear
  echo "********************************"
  echo "This is madness. This is Sparta!"
  echo "********************************"
  echo ""
  sleep 3

fi  

echo "*** Activating Blockain Sync ***"
sudo mkdir /mnt/hdd/${network}
echo "OK - sync is activated"

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info

# continue setup
./60finishHDD.sh
