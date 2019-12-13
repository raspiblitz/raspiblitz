#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

echo ""
echo "*** 30initHDD.sh ***"

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status ${network})
if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh status --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# check if HDD is mounted (secure against formatting a mounted disk with data)
echo "isMounted=${isMounted}"
if [ ${isMounted} -eq 1 ]; then
  echo "FAIL HDD/SSD is mounted - please unmount and call ./30initHDD.sh again"
  exit 1
fi

# check if HDD contains old RaspiBlitz data (secure against wrongly formatting)
echo "hddRaspiData=${hddRaspiData}"
if [ ${hddRaspiData} -eq 1 ]; then
  echo "FAIL HDD/SSD contains old data - please delete manual and call ./30initHDD.sh again"
  exit 1
fi

# check if there is a HDD connectecd to use as data drive
echo "hddCandidate=${hddCandidate}"
if [ ${#hddCandidate} -eq 0 ]; then
  echo "FAIL please cnnect a HDD and call ./30initHDD.sh again"
  exit 1
fi

# check minimal size of data drive needed
# bitcoin: 450 GB
# litecoin: 120 GB
minSize=450
if [ "${network}" = "litecoin" ]; then
  minSize=120
fi
if [ ${hddGigaBytes} -lt ${minSize} ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING: HDD is too small"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  echo "HDD was detected with the size of ${hddGigaBytes} GB"
  echo "For ${network} at least ${minSize} GB is needed"
  echo ""
  echo "If you want to change to a bigger HDD:"
  echo "* Unplug power of RaspiBlitz"
  echo "* Make a fresh SD card again"
  echo "* Start again with bigger HDD"
  exit
fi

# format drive if it does not have any blockchain or blitz data on it
# to be sure that HDD has no faulty partions, etc.
echo "hddGotBlockchain=${hddGotBlockchain}"
if [ ${hddGotBlockchain}  -eq 0 ]; then

  # test feature: if there is a USB stick as a raid connected, then format in BTRFS an not in EXT4
  format="ext4"
  if [ ${raidCandidates} -eq 1 ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "EXPERIMENTAL FEATURE: BTRFS + RAID"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "You connected an extra USB thumb drive to your RaspiBlitz."
    echo "This activates the exterimental feature of running BTRFS"
    echo "instead of EXT4 and is still unstable but needs testing."
    echo "PRESS ENTER to continue with BTRFS+RAID setup or press"
    echo "CTRL+C, remove device & call ./30initHDD.sh again."
    read key
    format="btrfs"
  fi

  # now partition/format HDD
  echo "formatting HDD/SSD ..."
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh format ${format} ${hddCandidate})
  if [ ${#error} -gt 0 ]; then
    echo "FAIL blitz.datadrive.sh format --> ${error}"
    echo "Please report issue to the raspiblitz github."
    exit 1
  fi

fi

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=30/g" /home/admin/raspiblitz.info

# automatically now add the HDD to the system
./40addHDD.sh


