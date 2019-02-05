#!/bin/bash
echo ""

## get basic info
source /home/admin/raspiblitz.info

echo "*** Adding HDD to the System ***"
echo "started from state(${state})"
sleep 5
existsHDD=$(lsblk | grep -c sda)
if [ ${existsHDD} -gt 0 ]; then
  echo "OK - HDD found as sda"
  mountOK=$(df | grep -c /mnt/hdd)
  if [ ${mountOK} -eq 1 ]; then
    echo "FAIL - HDD is already mounted"
    echo "If you want to add HDD freshly to the system, then unmount the HDD first and try again"
  else
    echo ""
    echo "*** Check HDD ***"
    formatExt4OK=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN | grep -c ext4) 
    if [ ${formatExt4OK} -eq 1 ]; then
      echo "OK - HDD is formatted with ext4 and is named BLOCKCHAIN"
      uuid=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN)
      set -- $uuid
      uuid=$1
      fstabOK=$(cat /etc/fstab | grep -c ${uuid})
      if [ ${fstabOK} -eq 0 ]; then
        fstabAdd="UUID=${uuid} /mnt/hdd ext4 noexec,defaults 0 0"
        echo "Adding line to /etc/fstab ..."
        echo ${fstabAdd}
        # adding the new line after line 3 to the /etc/fstab
        sudo sed "3 a ${fstabAdd}" -i /etc/fstab
      else
        echo "UUID is already in /etc/fstab"
      fi
      fstabOK=$(cat /etc/fstab | grep -c ${uuid})
      if [ ${fstabOK} -eq 1 ]; then
        echo "OK - HDD is listed in /etc/fstab"
        echo ""
        echo "*** Mount HDD ***"
        sudo mkdir /mnt/hdd
        sudo mount -a
        mountOK=$(df | grep -c /mnt/hdd)
        if [ ${mountOK} -eq 1 ]; then
          echo "OK - HDD is mounted"
	        echo ""

          # init the RASPIBLITZ Config
          source /home/admin/_version.info
          configFile="/mnt/hdd/raspiblitz.conf"
          sudo touch $configFile
          sudo chmod 777 ${configFile}
          echo "# RASPIBLITZ CONFIG FILE" > $configFile
          echo "raspiBlitzVersion='${codeVersion}'" >> $configFile
          echo "network=${network}" >> $configFile
          echo "chain=${chain}" >> $configFile
          echo "hostname=${hostname}" >> $configFile

          # move SSH pub keys to HDD so that they survive an update
          echo "moving SSH pub keys to HDD"
          sudo cp -r /etc/ssh /mnt/hdd/ssh
          sudo rm -rf /etc/ssh
          sudo ln -s /mnt/hdd/ssh /etc/ssh
          echo "OK"
          echo ""

          # set SetupState
          sudo sed -i "s/^setupStep=.*/setupStep=40/g" /home/admin/raspiblitz.info

          echo "*** Analysing HDD Content ***"
          if [  -d "/mnt/hdd/${network}"  ]; then 
            sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin 2>/dev/null
            sudo chown -R bitcoin:bitcoin /mnt/hdd/litecoin 2>/dev/null
            echo "Looks like the HDD is prepared with the Blockchain."

            if [ "${state}" = "recovering" ]; then
              # when HDD got added on update/provisioning
              echo "OK HDD got added ... returning to provisioning"
              exit 1
            else
              # when normal setup
              echo "Continuing with finishing the system setup ..."
              ./60finishHDD.sh
            fi

          else
            # HDD is empty - let setupBlitz - display next options
            echo "HDD empty --> go setup"
            ./10setupBlitz.sh
          fi # END Analysing HDD Content

	      else
           echo "FAIL - was not able to mount"
	      fi # END Mount check

      else
      	echo "FAIL - was not able to edit /etc/fstab"
      fi 

    else
      echo "FAIL - the HDD is not in ext4 format AND named 'BLOCKCHAIN'"
    fi
    
  fi
else
  echo "FAIL - no HDD as device sda found"
  echo "check if HDD is properly connected and has enough power - then try again with reboot"
fi
