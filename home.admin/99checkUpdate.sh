#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
source /home/admin/_version.info

clear

# get latest release version from GitHub
sudo curl -s -X GET https://raw.githubusercontent.com/rootzoll/raspiblitz/master/home.admin/_version.info > /home/admin/.version.tmp
gitHubVersionMain=$(cut -d"=" -f2 /home/admin/.version.tmp | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")
gitHubVersionSub=$(cut -d"=" -f2 /home/admin/.version.tmp | cut -d'"' -f2 | cut -d"." -f2 | egrep "^[0-9]")
sudo shred /home/admin/.version.tmp
sudo rm /home/admin/.version.tmp 2>/dev/null

# check valid version info
if [ ${#gitHubVersionMain} -eq 0 ] || [ ${#gitHubVersionSub} -eq 0 ]; then
  echo "FAIL: Was not able to get latest release Version from GitHub."
  echo "PRESS ENTER to continue."
  read key
  exit 1
fi

# get local version
localVersionMain=$(cut -d"=" -f2 /home/admin/_version.info | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")
localVersionSub=$(cut -d"=" -f2 /home/admin/_version.info | cut -d'"' -f2 | cut -d"." -f2 | egrep "^[0-9]")

echo "github  version: ${gitHubVersionMain}.${gitHubVersionSub}"
echo "local version: ${localVersionMain}.${localVersionSub}"

# compare versions
newerVersionAvailable=0
if [ ${gitHubVersionMain} -gt ${localVersionMain} ]; then
  echo "Main version is higher ..."
  newerVersionAvailable=1
else
  if [ ${gitHubVersionMain} -lt ${localVersionMain} ]; then
    echo "Strange that GutHub main version is lower then local - you maybe using a early release."
  elif [ ${gitHubVersionSub} -gt ${localVersionSub} ]; then
  echo "Sub version is higher ..."
  newerVersionAvailable=1
  fi
fi

# give feedback on version number
if [ ${newerVersionAvailable} -eq 0 ]; then
  dialog --title " Update Check " --yes-button "OK" --no-button "Update Anyway" --yesno "
OK. You are running the newest version of RaspiBlitz.
      " 7 57
  if [ $? -eq 0 ]; then
    exit 1
  fi
  clear
else

  whiptail --title "Update Check" --yes-button "Yes" --no-button "Not Now" --yesno "
There is a new Version of RaspiBlitz available.
You are running: ${localVersionMain}.${localVersionSub}
New Version: ${gitHubVersionMain}.${gitHubVersionSub}

Do you want more Information on how to update?
      " 12 52
  if [ $? -eq 1 ]; then
    exit 1
  fi
fi

whiptail --title "Update Instructions" --yes-button "Not Now" --no-button "Start Update" --yesno "To update your RaspiBlitz to a new version:

- Download the new SD card image to your laptop:
  https://github.com/rootzoll/raspiblitz
- Flash that SD card image to a new SD card
- Choose 'Start Update' below.

No need to close channels or download blockchain again.

Do you want to start the Update now?
      " 16 62
if [ $? -eq 0 ]; then
  exit 1
fi

whiptail --title "LND Data Backup" --yes-button "Download Backup" --no-button "Skip" --yesno "
Before we start the RaspiBlitz Update process,
its recommended to make a backup of all your LND Data
and download that file to your laptop.

Do you want to download LND Data Backup now?
      " 12 58
if [ $? -eq 0 ]; then
  clear
  echo "*************************************"
  echo "* PREPARING LND BACKUP DOWNLOAD"
  echo "*************************************"
  echo "please wait .."
  sleep 2
  /home/admin/config.scripts/lnd.rescue.sh backup
  echo
  echo "PRESS ENTER to continue once your done downloading."
  read key
else
  clear
  echo "*************************************"
  echo "* JUST MAKING BACKUP TO OLD SD CARD"
  echo "*************************************"
  echo "please wait .."
  sleep 2
  /home/admin/config.scripts/lnd.rescue.sh backup no-download
fi

whiptail --title "READY TO UPDATE?" --yes-button "START UPDATE" --no-button "Cancel" --yesno "If you start the update: The RaspiBlitz will power down.
Once the LCD is white and no LEDs are blicking anymore:

- Remove the Power from RaspiBlitz
- Exchange the old with the new SD card
- Connect Power back to the RaspiBlitz
- Follow the instructions on the LCD

Do you have the SD card with the new version image ready
and do you WANT TO START UPDATE NOW?
      " 16 62

if [ $? -eq 1 ]; then
  dialog --title " Update Canceled " --msgbox "
OK. RaspiBlitz will NOT update now.
      " 7 39
  sudo systemctl start lnd
  exit 1
fi

clear
sudo shutdown now
