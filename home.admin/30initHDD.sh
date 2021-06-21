#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

clear
echo ""
echo "# *** 30initHDD.sh ***"
echo
echo "# --> Checking HDD/SSD status..."

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status ${network})
if [ ${#error} -gt 0 ]; then
  echo "# FAIL blitz.datadrive.sh status --> ${error}"
  echo "# Please report issue to the raspiblitz github."
  exit 1
fi

# check if HDD is mounted (secure against formatting a mounted disk with data)
echo "isMounted=${isMounted}"
if [ ${isMounted} -eq 1 ]; then
  echo "# FAIL HDD/SSD is mounted - please unmount and call ./30initHDD.sh again"
  exit 1
fi

# check if HDD contains old RaspiBlitz data (secure against wrongly formatting)
echo "hddRaspiData=${hddRaspiData}"
if [ ${hddRaspiData} -eq 1 ]; then
  echo "# FAIL HDD/SSD contains old data - please delete manual and call ./30initHDD.sh again"
  exit 1
fi

# check if there is a HDD connected to use as data drive
echo "hddCandidate=${hddCandidate}"
if [ ${#hddCandidate} -eq 0 ]; then
  echo "# FAIL please connect a HDD and call ./30initHDD.sh again"
  exit 1
fi
echo "OK"

# check minimal size of data drive needed
echo
echo "# --> Check HDD/SSD for Size ..."
# bitcoin: 400 GB
# litecoin: 120 GB
minSize=400
if [ "${network}" = "litecoin" ]; then
  minSize=120
fi
if [ ${hddGigaBytes} -lt ${minSize} ]; then
  echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "# WARNING: HDD is too small"
  echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  echo "# HDD was detected with the size of ${hddGigaBytes} GB"
  echo "# For ${network} at least ${minSize} GB is needed"
  echo ""
  echo "# If you want to change to a bigger HDD:"
  echo "# * Unplug power of RaspiBlitz"
  echo "# * Make a fresh SD card again"
  echo "# * Start again with bigger HDD"
  exit 1
fi
echo " OK"

# format drive if it does not have any blockchain or blitz data on it
# to be sure that HDD has no faulty partitions, etc.
echo
echo "# --> Check HDD/SSD for Blockchain ..."
echo "# hddGotBlockchain=${hddGotBlockchain}"
raidSizeGB=$(echo "${raidCandidate[0]}" | cut -d " " -f 2) 
echo "# raidCandidates=${raidCandidates}"
echo "# raidSizeGB=${raidSizeGB}"
if [ "${hddGotBlockchain}" == "" ] || [ ${hddGotBlockchain}  -eq 0 ]; then

  format="ext4"

  # test feature: if there is a USB stick as a raid connected, then format in BTRFS an not in EXT4
  if [ ${raidCandidates} -eq 1 ] && [ ${raidSizeGB} -gt 14 ]; then

    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# EXPERIMENTAL FEATURE: BTRFS + RAID"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# You connected an extra USB thumb drive to your RaspiBlitz."
    echo "# This activates the experimental feature of running BTRFS"
    echo "# instead of EXT4 and is still unstable but needs testing."
    echo "# PRESS ENTER to continue with BTRFS+RAID setup or press"
    echo "# CTRL+C, remove device & call ./30initHDD.sh again."
    read key
    format="btrfs"

    # check that raid candidate is big enough
    # a 32GB drive gets shown with 28GB in my tests
    if [ ${raidSizeGB} -lt 27 ]; then
      echo "# FAIL the raid device needs to be at least a 32GB thumb drive."
      echo "# Please remove or replace and call ./30initHDD.sh again"
      exit 1
    fi

  elif [ ${raidCandidates} -gt 1 ]; then
    echo "# FAIL more then one USB raid drive candidate connected."
    echo "# Please max one extra USB drive and the call ./30initHDD.sh again"
    exit 1
  fi


  # now partition/format HDD
  echo
  if (whiptail --title "FORMAT HDD/SSD" --yesno "The connected hard drive needs to get formatted.\nIMPORTANT: This will delete all data on that drive." 8 56); then
    clear
    echo "# --> Formatting HDD/SSD ..."
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh format ${format} ${hddCandidate})
    if [ ${#error} -gt 0 ]; then
      echo "# FAIL blitz.datadrive.sh format --> ${error}"
      echo "# Please report issue to the raspiblitz github."
      exit 1
    fi
   else
    clear
    echo "# Not formatting the HDD/SSD - Setup Process stopped."
    echo "# Rearrange your hardware and restart with a fresh sd card again."
    exit 1
  fi

fi
echo "# OK"

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=30/g" /home/admin/raspiblitz.info

# automatically now add the HDD to the system
./40addHDD.sh


