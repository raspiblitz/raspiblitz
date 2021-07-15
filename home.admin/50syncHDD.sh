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
    msg="$msg can take multiple days - even weeks\n"
    msg="$msg Its recommended to use another option.\n"
    msg="$msg \n"
    msg="$msg So do you really want start syncing now?"
    dialog --title " WARNING " --yesno "${msg}" 11 57
    response=$?
    case $response in
      0) echo "--> OK";;
      1) exit 1;;
      255) exit 1;;
    esac
  fi
fi

# ask if really sync behind Tor
# if [ "${runBehindTor}" = "on" ]; then
#  whiptail --title ' Sync Blockchain from behind Tor? ' --yes-button='Public-Sync' --no-button='Tor-Sync' --yesno "You decided to run your node behind Tor and validate the blockchain with your RaspiBlitz - thats good. But downloading the complete blockchain thru Tor can add some extra time (maybe a day) to the process and adds a heavy load on the Tor network.\n
#Your RaspiBlitz can just run the initial blockchain download with your public IP (Public-Sync) but keep your Lighting node safe behind Tor.
#It would speed up the self-validation while not revealing your Lightning node identity. But for most privacy choose (Tor-Sync).
#  " 15 76
#  if [ $? -eq 0 ]; then
#    # set flag to not run bitcoin behind Tor during IDB
#    echo "ibdBehindTor=off" >> /home/admin/raspiblitz.info
#  fi
#fi

echo "**********************************"
echo "Dont Trust, verify - starting sync"
echo "**********************************"
echo ""
sleep 3


echo "*** Optimizing RAM for Sync ***"

kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
echo "dont forget to reduce dbcache once IBD is done" > "/home/admin/selfsync.flag"
# RP4 4GB
if [ ${kbSizeRAM} -gt 3500000 ]; then
  echo "Detected RAM >=4GB --> optimizing ${network}.conf"
  sudo sed -i "s/^dbcache=.*/dbcache=3072/g" /home/admin/assets/${network}.conf
# RP4 2GB
elif [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >=2GB --> optimizing ${network}.conf"
  sudo sed -i "s/^dbcache=.*/dbcache=1536/g" /home/admin/assets/${network}.conf
# RP3/4 1GB
else
  echo "Detected RAM <=1GB --> optimizing ${network}.conf"
  sudo sed -i "s/^dbcache=.*/dbcache=512/g" /home/admin/assets/${network}.conf
fi

echo ""
echo "*** Activating Blockain Sync ***"

sudo mkdir /mnt/hdd/${network} 2>/dev/null
sudo /home/admin/XXcleanHDD.sh -blockchain -force
sudo -u bitcoin mkdir /mnt/hdd/${network}/blocks 2>/dev/null
sudo -u bitcoin mkdir /mnt/hdd/${network}/chainstate 2>/dev/null

# set so that 10raspiblitz.sh has a flag to see that resync is running
sudo touch /mnt/hdd/${network}/blocks/.selfsync
sudo sed -i "s/^state=.*/state=sync/g" /home/admin/raspiblitz.info

echo "OK - sync is activated"

if [ "${setupStep}" = "100" ]; then

  # start servives
  echo "reboot needed: shutdown -r now"

else

  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info

  # continue setup
  ./60finishHDD.sh

fi
