#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

echo ""
echo "# *** 40addHDD.sh ***"

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status ${network})
if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh status --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# temp mount
if [ "$hddFormat" == "btrfs" ]; then
   source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddCandidate})
else
   source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddPartitionCandidate})
fi

if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh tempmount --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# linking drives/directories
echo
echo "# --> Linking drives/directories"
echo "# hddCandidate='${hddCandidate}'"
echo "# hddPartitionCandidate='${hddPartitionCandidate}'"
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh link)
if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh link --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# adding drives to fstab for permanent mount
echo
echo "# --> Adding the data drive to OS ..."
echo "# hddCandidate='${hddCandidate}'"
echo "# hddPartitionCandidate='${hddPartitionCandidate}'"
echo "# hddFormat='${hddFormat}'"
if [ "$hddFormat" == "btrfs" ]; then
   source <(sudo /home/admin/config.scripts/blitz.datadrive.sh fstab ${hddCandidate})
else
   source <(sudo /home/admin/config.scripts/blitz.datadrive.sh fstab ${hddPartitionCandidate})
fi

if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh fstab --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# adding RAID drive
echo "# isBTRFS=${isBTRFS}"
echo "# raidCandidates=${raidCandidates}"
if [ ${isBTRFS} -eq 1 ] && [ ${raidCandidates} -eq 1 ]; then

    # example string: 'sdb 28 GB SanDisk'
    raidDevice=$(echo "${raidCandidate[0]}" | cut -d " " -f 1) 
    raidSizeGB=$(echo "${raidCandidate[0]}" | cut -d " " -f 2) 

    echo
    echo "# --> Adding Raid Drive ..."
    echo "# raidDevice='${raidDevice}'"
    echo "# raidSizeGB=${raidSizeGB}"
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh raid on ${raidDevice})
    if [ ${#error} -gt 0 ]; then
      echo "# FAIL blitz.datadrive.sh raid on --> ${error}"
      echo "# Please report issue to the raspiblitz github."
      exit 1
    fi

 fi

# init the RASPIBLITZ Config
echo
echo "# --> Init raspiblitz.conf ..."
configFile="/mnt/hdd/raspiblitz.conf"
configExists=$(sudo ls ${configFile} 2>/dev/null | grep -c 'raspiblitz.conf')
if [ ${configExists} -eq 1 ]; then

  # config exists - nothing much to do
  echo "# config file already exists on HDD/SSD"
  sudo chmod 777 ${configFile}

else

  # create file and use init values from raspiblitz.info
  echo "# CREATING new ${configFile}"
  source /home/admin/_version.info
  echo "# RASPIBLITZ CONFIG FILE" > /home/admin/raspiblitz.conf
  echo "raspiBlitzVersion='${codeVersion}'" >> /home/admin/raspiblitz.conf
  echo "network=${network}" >> /home/admin/raspiblitz.conf
  echo "chain=${chain}" >> /home/admin/raspiblitz.conf
  echo "hostname=${hostname}" >> /home/admin/raspiblitz.conf
  echo "displayClass=${displayClass}" >> /home/admin/raspiblitz.conf
  echo "displayType=${displayType}" >> /home/admin/raspiblitz.conf
  echo "lcdrotate=1" >> /home/admin/raspiblitz.conf

  sudo mv /home/admin/raspiblitz.conf $configFile
  sudo chown root:root ${configFile}
  sudo chmod 777 ${configFile}
  sleep 3

  # try to determine publicIP and make sure its in raspiblitz.conf
  # https://github.com/rootzoll/raspiblitz/issues/312#issuecomment-462675101
  /home/admin/config.scripts/internet.sh update-publicip

fi

# link ssh directory from SD card to HDD
echo "# --> SSH key settings"
echo "# copying SSH pub keys to HDD"
sudo cp -r /etc/ssh /mnt/hdd/ssh
# just copy dont link anymore
# see: https://github.com/rootzoll/raspiblitz/issues/1798
#sudo rm -rf /etc/ssh
#sudo ln -s /mnt/hdd/ssh /etc/ssh
#sudo /home/admin/config.scripts/blitz.systemd.sh update-sshd
echo "# OK"
echo ""

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=40/g" /home/admin/raspiblitz.info

# check if HDD contains a blockchain to work with
echo "hddGotBlockchain=${hddGotBlockchain}"
if [ ${hddGotBlockchain} -eq 1 ]; then
  
  echo "# Looks like the HDD is prepared with the Blockchain."

  # ask user if prepared blockchain is to use or self-validate
  whiptail --title ' Use Blockchain from HDD/SSD? ' --yes-button='Continue' --no-button='DELETE' --yesno "
On the HDD/SSD Blockchain data was found.\n
Continue if you trust that data to be valid.\n
If you dont trust that data you can now choose to delete it - but keep in mind that this can add multiple days of waiting time to your setup process to regain or self-validate the initial blockchain data.
  " 14 75
  if [ $? -eq 1 ]; then
    # DELETE
    echo "# Deleting old blockchain data .."
    sudo rm -R /mnt/hdd/bitcoin 2>/dev/null
    sudo rm -R /mnt/hdd/litecoin 2>/dev/null
    # HDD is now empty - let setupBlitz - display next options
    echo "# HDD now empty --> follow further setup"
    ./10setupBlitz.sh
  else
    # CONTINUE
    echo "# Continuing with finishing the system setup ..."
    ./60finishHDD.sh
  fi

else

  # HDD is empty - let setupBlitz - display next options
  echo "# HDD empty --> follow further setup"
  ./10setupBlitz.sh

fi
