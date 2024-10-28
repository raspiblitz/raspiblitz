#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 >&2 echo "# managing the data drive(s) with old EXT4 or new BTRFS"
 >&2 echo "# blitz.datadrive.sh [status|tempmount|unmount|format|fstab|raid|link|swap|clean|snapshot|uasp-fix]"
 echo "error='missing parameters'"
 exit 1
fi

###################
# BASICS
###################

# TO UNDERSTAND THE BTFS HDD LAYOUT:
####################################
# 1) BLITZDATA - a BTRFS partition for all RaspiBlitz data - 30GB
#    here put all files of LND, app, etc that need backup
# 2) BLITZSTORAGE - a BTFRS partition for mostly Blockchain data
#    all data here can get lost and rebuild if needed (Blockchain, Indexes, etc)
# 3) BLITZTEMP - a FAT partition just for SWAP & Exchange - 34GB
#    used for SWAP file and easy to read from Win32/MacOS for exchange
#    this directory should get cleaned on every start (except from swap)

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})"


# install smartmontools if needed
smartmontoolsInstalled=$(apt-cache policy smartmontools | grep -c 'Installed: (none)' | grep -c "0")
if [ ${smartmontoolsInstalled} -eq 0 ]; then
  >&2 echo "# Installing smartmontools ..."
  apt-get install -y smartmontools 1>/dev/null
fi
smartmontoolsInstalled=$(apt-cache policy smartmontools | grep -c 'Installed: (none)' | grep -c "0")
if [ ${smartmontoolsInstalled} -eq 0 ]; then
  echo "error='missing smartmontools package'"
  exit 1
fi

###################
# STATUS
###################

# gathering system info
# is global so that also other parts of this script can use this

# check if a btrfs filesystem is available
# basics
isMounted=$(df | grep -c /mnt/hdd)
isBTRFS="0"
isRaid="0"
isZFS="0"
isSSD="0"
isSMART="0"

# BTRFS extras
btrfsConnected=$(lsblk -f | grep -c btrfs)
if [ ${btrfsConnected} -gt 0 ]; then

  # install BTRFS if needed
  btrfsInstalled=$(btrfs --version 2>/dev/null | grep -c "btrfs-progs")
  if [ ${btrfsInstalled} -eq 0 ]; then
    >&2 echo "# Installing BTRFS ..."
    apt-get install -y btrfs-progs 1>/dev/null
  fi
  btrfsInstalled=$(btrfs --version 2>/dev/null | grep -c "btrfs-progs")
  if [ ${btrfsInstalled} -eq 0 ]; then
    echo "error='missing btrfs package'"
    exit 1
  fi
  isBTRFS=$(btrfs filesystem show 2>/dev/null| grep -c 'BLITZSTORAGE')
  isRaid=$(btrfs filesystem df /mnt/hdd 2>/dev/null | grep -c "Data, RAID1")

fi

# ZFS extras
zfsConnected=$(lsblk -f | grep -c zfs)
if [ ${zfsConnected} -gt 0 ]; then
  isZFS=$(zfs list 2>/dev/null | grep -c "/mnt/hdd")
fi

# determine if swap is external on or not
externalSwapPath="/mnt/hdd/swapfile"
if [ ${isBTRFS} -eq 1 ]; then
  externalSwapPath="/mnt/temp/swapfile"
fi
isSwapExternal=$(swapon -s | grep -c "${externalSwapPath}")

# output and exit if just status action
if [ "$1" = "status" ]; then

  # optional second parameter can be 'bitcoin'
  blockchainType=$2

  echo "# RASPIBLITZ DATA DRIVE Status"  
  echo

  echo "# BASICS"
  echo "isMounted=${isMounted}"
  echo "isBTRFS=${isBTRFS}"

  # if HDD is not mounted system then it is in the pre-setup phase
  # deliver all the detailes needed about the data drive
  # and it content for the setup dialogs
  if [ ${isMounted} -eq 0 ]; then
    echo
    echo "# SETUP INFO"

    # find the HDD (biggest single partition)
    # will then be used to offer formatting and permanent mounting
    hdd=""
    sizeDataPartition=0
    OSPartition=$(df /usr 2>/dev/null | grep dev | cut -d " " -f 1 | sed "s#/dev/##g")
    # detect boot partition on UEFI systems
    bootPartition=$(df /boot/efi 2>/dev/null | grep dev | cut -d " " -f 1 | sed "s#/dev/##g")
    if [ ${#bootPartition} -eq 0 ]; then
      # for non UEFI
      bootPartition=$(df /boot 2>/dev/null | grep dev | cut -d " " -f 1 | sed "s#/dev/##g")
    fi
    lsblk -o NAME,SIZE -b | grep -P "[s|vn][dv][a-z][0-9]?" > .lsblk.tmp
    while read line; do
      # cut line info into different informations
      testname=$(echo $line | cut -d " " -f 1 | sed 's/[^a-z0-9]*//g')
      if [ $(echo $line | grep -c "nvme") = 0 ]; then
        testdevice=$(echo $testname | sed 's/[^a-z]*//g')
	      testpartition=$(echo $testname | grep -P '[a-z]{3,5}[0-9]{1}')
      else
	      testdevice=$(echo $testname | sed 's/\([^p]*\).*/\1/')
	      testpartition=$(echo $testname | grep -P '[p]{1}')
      fi
	  
      if [ ${#testpartition} -gt 0 ]; then
        testsize=$(echo $line | sed "s/  */ /g" | cut -d " " -f 2 | sed 's/[^0-9]*//g')
      else
        testsize=0
      fi

      # echo "# line($line)"
      # echo "# testname(${testname}) testdevice(${testdevice}) testpartition(${testpartition}) testsize(${testsize})"

      # count partitions
      testpartitioncount=0
      if [ ${#testdevice} -gt 0 ]; then
        testpartitioncount=$(fdisk -l | grep /dev/$testdevice | wc -l)
        # do not count line with disk info
        testpartitioncount=$((testpartitioncount-1))
      fi

      if [ "$(uname -m)" = "x86_64" ]; then
	      
        # For PC systems

        if [ $(echo "$testpartition" | grep -c "nvme")  = 0 ]; then
          testParentDisk=$(echo "$testpartition" | sed 's/[^a-z]*//g')
	      else
          testParentDisk=$(echo "$testpartition" | sed 's/\([^p]*\).*/\1/')
   	    fi
	      
        if [ $(echo "$OSPartition" | grep -c "nvme")  = 0 ]; then
          OSParentDisk=$(echo "$OSPartition" | sed 's/[^a-z]*//g')
	      else
          OSParentDisk=$(echo "$OSPartition" | sed 's/\([^p]*\).*/\1/')
        fi
        
        if [ $(echo "$bootPartition" | grep -c "nvme")  = 0 ]; then	
          bootParentDisk=$(echo "$bootPartition" | sed 's/[^a-z]*//g')
	      else
	        bootParentDisk=$(echo "$bootPartition" | sed 's/\([^p]*\).*/\1/')
	      fi
		  
        if [ "$testdevice" != "$OSParentDisk" ] && [ "$testdevice" != "$bootParentDisk" ];then
          sizeDataPartition=${testsize}
          hddDataPartition="${testpartition}"
          hdd="${testdevice}"
        fi

      elif [ $testpartitioncount -gt 0 ]; then
        # if a partition was found - make sure to skip the OS and boot partitions
        # echo "# testpartitioncount > 0"
        if [ "${testpartition}" != "${OSPartition}" ] && [ "${testpartition}" != "${bootPartition}" ]; then
          # make sure to use the biggest
          if [ ${testsize} -gt ${sizeDataPartition} ]; then
            sizeDataPartition=${testsize}
            hddDataPartition="${testpartition}"
            hdd="${testdevice}"
          fi
        fi

      else
        # default hdd set, when there is no OSpartition and there might be no partitions at all
        # echo "# else"
        # echo "# testsize(${testsize})"
        # echo "# sizeDataPartition(${sizeDataPartition})"

        if [ "${OSPartition}" = "mmcblk0p2" ] && [ "${hdd}" = "" ] && [ "${testdevice}" != "" ]; then
          # echo "# OSPartition = mmcblk0p2"
          hdd="${testdevice}"
        fi

	      # make sure to use the biggest
        if [ ${testsize} -gt ${sizeDataPartition} ]; then
	        # Partition to be created is smaller than disk so this is not correct (but close)
          # echo "# testsize > sizeDataPartition"
          sizeDataPartition=$(fdisk -l /dev/$testdevice | grep GiB | cut -d " " -f 5)
          hddDataPartition="${testdevice}1"
          hdd="${testdevice}"
	      fi

      fi

      # echo "# testpartitioncount($testpartitioncount)"
      # echo "# OSPartition(${OSPartition})"
      # echo "# bootPartition(${bootPartition})"
      # echo "# hdd(${hdd})"

    done < .lsblk.tmp
    rm -f .lsblk.tmp 1>/dev/null 2>/dev/null

    # display possible warnings from hdd partition detection
    if [ "${hddPartitionCandidate}" != "" ] && [ ${#hddDataPartition} -lt 4 ]; then
      echo "# WARNING: found invalid partition (${hddDataPartition}) - redacting"
      hddDataPartition=""
    fi

    # try to detect if its an SSD
    isSMART=$(smartctl -a /dev/${hdd} | grep -c "Serial Number:")
    echo "isSMART=${isSMART}"
    isSSD=1
    isRotational=$(echo "${smartCtlA}" | grep -c "Rotation Rate:")
    if [ ${isRotational} -gt 0 ]; then
      isSSD=$(echo "${smartCtlA}" | grep "Rotation Rate:" | grep -c "Solid State Device")
    fi
    echo "isSSD=${isSSD}"
    hddTemp=""
    echo "hddTemperature="
    echo "hddTemperatureStr='?°C'"

    hddBytes=0
    hddGigaBytes=0
    if [ "${hdd}" != "" ]; then
      hddBytes=$(fdisk -l /dev/$hdd | grep GiB | cut -d " " -f 5)
      if [ "${hddBytes}" = "" ]; then
	      hddBytes=$(fdisk -l /dev/$hdd | grep TiB | cut -d " " -f 5)
      fi
      hddGigaBytes=$(echo "scale=0; ${hddBytes}/1024/1024/1024" | bc -l)
    fi

    # check if big enough
    if [ ${hddGigaBytes} -lt 130 ]; then
      echo "# Found HDD '${hdd}' is smaller than 130GB"
      hdd=""
      hddDataPartition=""
    fi

    # display results from hdd & partition detection
    echo "hddCandidate='${hdd}'"
    echo "hddBytes=${hddBytes}"
    echo "hddGigaBytes=${hddGigaBytes}"
    echo "hddPartitionCandidate='${hddDataPartition}'"

    # if positive deliver more data
    if [ ${#hddDataPartition} -gt 0 ]; then
      # check partition size in bytes and GBs
      echo "hddDataPartitionBytes=${sizeDataPartition}"
      hddDataPartitionGigaBytes=$(echo "scale=0; ${sizeDataPartition}/1024/1024/1024" | bc -l)
      echo "hddPartitionGigaBytes=${hddDataPartitionGigaBytes}"
      
      # check format of devices partition
      hddFormat=$(lsblk -o FSTYPE,NAME,TYPE | grep part | grep "${hddDataPartition}" | cut -d " " -f 1)
      echo "hddFormat='${hddFormat}'"

      # if 'ext4' or 'btrfs' then temp mount and investigate content
      if [ "${hddFormat}" = "ext4" ] || [ "${hddFormat}" = "btrfs" ]; then
        # BTRFS is working with subvolumes for snapshots / ext4 has no SubVolumes
        subVolumeDir=""
        if [ "${hddFormat}" = "btrfs" ]; then
          subVolumeDir="/WORKINGDIR"
        fi

        # temp mount data drive
        mountError=""
        mkdir -p /mnt/hdd
        if [ "${hddFormat}" = "ext4" ]; then
	  hddDataPartitionExt4=$hddDataPartition
          mountError=$(mount /dev/${hddDataPartitionExt4} /mnt/hdd 2>&1)
          isTempMounted=$(df | grep /mnt/hdd | grep -c ${hddDataPartitionExt4})
        fi
        if [ "${hddFormat}" = "btrfs" ]; then
          mountError=$(mount -o degraded /dev/${hdd}1 /mnt/hdd 2>&1)
          isTempMounted=$(df | grep /mnt/hdd | grep -c ${hdd})
        fi

        # check for mount error
        if [ ${#mountError} -gt 0 ] || [ ${isTempMounted} -eq 0 ]; then
          echo "hddError='data mount failed'"
        else

          #####################################
          # Pre-Setup Investigation of DATA-PART
          # make copy of raspiblitz.conf & 

          # check for recoverable RaspiBlitz data (if config file exists) and raid 
          hddRaspiData=$(ls -l /mnt/hdd${subVolumeDir} 2>/dev/null | grep -c raspiblitz.conf)
          echo "hddRaspiData=${hddRaspiData}"
          hddRaspiVersion=""
          if [ ${hddRaspiData} -eq 1 ]; then

            # output version data from raspiblitz.conf
            source /mnt/hdd${subVolumeDir}/raspiblitz.conf
            echo "hddRaspiVersion='${raspiBlitzVersion}'"

            # create hdd-inspect data dir on RAMDISK
            mkdir /var/cache/raspiblitz/hdd-inspect 2>/dev/null

            # make copy of raspiblitz.conf to RAMDISK
            cp -a /mnt/hdd${subVolumeDir}/raspiblitz.conf /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf

            # make copy of WIFI config to RAMDISK (if available)
            cp -a /mnt/hdd${subVolumeDir}/app-data/wifi /var/cache/raspiblitz/hdd-inspect/ 2>/dev/null

            # Convert old ssh backup data structure (if needed)
            oldDataExists=$(sudo ls /mnt/hdd${subVolumeDir}/ssh/ssh_host_rsa_key 2>/dev/null | grep -c "ssh_host_rsa_key")
            if [ "${oldDataExists}" != "0" ]; then
              # make a complete backup of directory
              cp -a /mnt/hdd${subVolumeDir}/ssh /mnt/hdd${subVolumeDir}/app-storage/ssh-old-backup
              # delete old false sub directory (if exists)
              rm -r /mnt/hdd${subVolumeDir}/ssh/ssh 2>/dev/null
              # move ssh root keys into new directory (if exists)
              mv /mnt/hdd${subVolumeDir}/ssh/root_backup /mnt/hdd${subVolumeDir}/app-data/ssh-root 2>/dev/null
              # move sshd keys into new directory
              mkdir -p /mnt/hdd${subVolumeDir}/app-data/sshd 2>/dev/null
              mv /mnt/hdd${subVolumeDir}/ssh /mnt/hdd${subVolumeDir}/app-data/sshd/ssh
            fi

            # make copy of SSH keys to RAMDISK (if available)
            cp -a /mnt/hdd${subVolumeDir}/app-data/sshd /var/cache/raspiblitz/hdd-inspect 2>/dev/null
            cp -a /mnt/hdd${subVolumeDir}/app-data/ssh-root /var/cache/raspiblitz/hdd-inspect 2>/dev/null
          fi
        
          # comment this line out if case to study the contect of the data section
          umount /mnt/hdd
        fi

        # temp storage data drive
        mkdir -p /mnt/storage
	if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
	  nvp=""
	else
	  nvp="p"
	fi
        if [ "${hddFormat}" = "btrfs" ]; then
          # in btrfs setup the second partition is storage partition
          mount /dev/${hdd}${nvp}2 /mnt/storage 2>/dev/null
          isTempMounted=$(df | grep /mnt/storage | grep -c ${hdd})
        else
          # in ext4 setup the partition is also the storage partition
          mount /dev/${hddDataPartitionExt4} /mnt/storage 2>/dev/null
          isTempMounted=$(df | grep /mnt/storage | grep -c ${hddDataPartitionExt4})
        fi
        if [ ${isTempMounted} -eq 0 ]; then
          echo "hddError='storage mount failed'"
        else

          ########################################
          # Pre-Setup Invetigation of STORAGE-PART

          # check for blockchain data on storage
          hddBlocksBitcoin=$(ls /mnt/storage${subVolumeDir}/bitcoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
          echo "hddBlocksBitcoin=${hddBlocksBitcoin}"
          if [ "${blockchainType}" = "bitcoin" ] && [ ${hddBlocksBitcoin} -eq 1 ]; then
            echo "hddGotBlockchain=1"
          elif [ ${#blockchainType} -gt 0 ]; then
            echo "hddGotBlockchain=0"
          fi

          # check free space on data drive
          if [ ${isBTRFS} -eq 0 ]; then
            # EXT4
            hdd_data_free1Kblocks=$(df -h -k /dev/${hddDataPartitionExt4} | grep "/dev/${hddDataPartitionExt4}" | sed -e's/  */ /g' | cut -d" " -f 4 | tr -dc '0-9')
          else
            # BRTS
            hdd_data_free1Kblocks=$(df -h -k /dev/${hdd}${nvp}1 | grep "/dev/${hdd}${nvp}1" | sed -e's/  */ /g' | cut -d" " -f 4 | tr -dc '0-9')
          fi
          if [ "${hdd_data_free1Kblocks}" != "" ]; then
            hddDataFreeBytes=$((${hdd_data_free1Kblocks} * 1024))
            hddDataFreeGB=$((${hdd_data_free1Kblocks} / (1024 * 1024)))
            echo "hddDataFreeBytes=${hddDataFreeBytes}"
            echo "hddDataFreeKB=${hdd_data_free1Kblocks}"
            echo "hddDataFreeGB=${hddDataFreeGB}"
          else
            echo "# ERROR: Was not able to determine hddDataFree space"
          fi

          # check if its another fullnode implementation data disk
          hddGotMigrationData=""
          hddGotMigrationDataExtra=""
          if [ "${hddFormat}" = "ext4" ]; then
            # check for other node implementations
            isUmbrelHDD=$(ls /mnt/storage/umbrel/info.json 2>/dev/null | grep -c '.json')
            isCitadelHDD=$(ls /mnt/storage/citadel/info.json 2>/dev/null | grep -c '.json')
            isMyNodeHDD=$(ls /mnt/storage/mynode/bitcoin/bitcoin.conf 2>/dev/null | grep -c '.conf')
            if [ ${isUmbrelHDD} -gt 0 ]; then
              # sudo cat /mnt/hdd/umbrel/app-data/bitcoin/umbrel-app.yml | grep "version:" | cut -d ":" -f2 | tr -d \" | xargs
              hddGotMigrationData="umbrel"
              btcVersion=$(grep "lncm/bitcoind" /mnt/storage/umbrel/app-data/bitcoin/docker-compose.yml 2>/dev/null | sed 's/.*bitcoind://' | sed 's/@.*//')
              clnVersion=$(grep "lncm/clightning" /mnt/storage/umbrel/app-data/core-lightning/docker-compose.yml 2>/dev/null | sed 's/.*clightning://' | sed 's/@.*//')
              lndVersion=$(grep "lightninglabs/lnd" /mnt/storage/umbrel/app-data/lightning/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
              # umbrel <0.5.0 (old structure)
              if [ "${lndVersion}" == "" ]; then
                lndVersion=$(grep "lightninglabs/lnd" /mnt/storage/umbrel/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
              fi
              echo "hddVersionBTC='${btcVersion}'"
              echo "hddVersionCLN='${clnVersion}'"
              echo "hddVersionLND='${lndVersion}'"
            elif [ ${isMyNodeHDD} -gt 0 ]; then
              hddGotMigrationData="mynode"
            elif [ ${isCitadelHDD} -gt 0 ]; then
              hddGotMigrationData="citadel"
              lndVersion=$(grep "lightninglabs/lnd" /mnt/storage/citadel/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
              echo "hddVersionLND='${lndVersion}'"
            fi
          else
            echo "# not an ext4 drive - all known fullnode packages use ext4 at the moment"
          fi
          echo "hddGotMigrationData='${hddGotMigrationData}'"

          # comment this line out if case to study the content of the storage section
          umount /mnt/storage
        fi
      else
        # if not ext4 or btrfs - there is no usable data
        echo "hddRaspiData=0"
        echo "hddBlocksBitcoin=0"
        echo "hddGotBlockchain=0"
      fi
    fi
  else

    # STATUS INFO WHEN MOUNTED

    # output data drive
    if [ "${isBTRFS}" -gt 0 ]; then
      # on btrfs date the storage partition as the data partition
      hddDataPartition=$(df | grep "/mnt/storage$" | cut -d " " -f 1 | cut -d "/" -f 3)
    elif [ "${isZFS}" -gt 0 ]; then
      # a ZFS pool has no leading /
      hddDataPartition=$(df | grep "/mnt/hdd$" | cut -d " " -f 1 | cut -d "/" -f 2)
      if [ ${#hddDataPartition} -eq 0 ];then
        # just a pool, no filesystem
        hddDataPartition=$(df | grep "/mnt/hdd$" | cut -d " " -f 1 | cut -d "/" -f 1)
      fi
    else
      # on ext4 its the whole /mnt/hdd
      hddDataPartition=$(df | grep "/mnt/hdd$" | cut -d " " -f 1 | cut -d "/" -f 3)
    fi
    if [ $(echo "${hddDataPartition}" | grep -c "nvme")  = 0 ]; then
      hdd=$(echo $hddDataPartition | sed 's/[0-9]*//g')
    else
      hdd=$(echo "$hddDataPartition" | sed 's/\([^p]*\).*/\1/')
    fi
    hddFormat=$(lsblk -o FSTYPE,NAME,TYPE | grep part | grep "${hddDataPartition}" | cut -d " " -f 1)
    if [ "${hddFormat}" = "ext4" ]; then
       hddDataPartitionExt4=$hddDataPartition
    fi
    hddRaspiData=$(ls -l /mnt/hdd | grep -c raspiblitz.conf)
    echo "hddRaspiData=${hddRaspiData}"
    hddRaspiVersion=""
    if [ ${hddRaspiData} -eq 1 ]; then
      source /mnt/hdd/raspiblitz.conf
      hddRaspiVersion="${raspiBlitzVersion}"
    fi
    echo "hddRaspiVersion='${hddRaspiVersion}'"

    smartCtlA=$(smartctl -a /dev/${hdd} | tr -d '"')

    # try to detect if its an SSD
    isSMART=$(echo "${smartCtlA}" | grep -c "Serial Number:")
    echo "isSMART=${isSMART}"

    isSSD=1
    isRotational=$(echo "${smartCtlA}" | grep -c "Rotation Rate:")
    if [ ${isRotational} -gt 0 ]; then
      isSSD=$(echo "${smartCtlA}" | grep "Rotation Rate:" | grep -c "Solid State Device")
    fi
    echo "isSSD=${isSSD}"

    echo "datadisk='${hdd}'"
    echo "datapartition='${hddDataPartition}'"
    echo "hddCandidate='${hdd}'"
    echo "hddPartitionCandidate='${hddDataPartition}'"

    # check temp if possible
    hddTemp=$(echo "${smartCtlA}" | grep "^Temperature" | head -n 1 | grep -o '[0-9]\+')
    if [ hddTemp = "" ]; then
      hddTemp=$(echo "${smartCtlA}" | grep "^194" | tr -s ' ' | cut -d" " -f 10 | grep -o '[0-9]\+')
    fi
    echo "hddTemperature=${hddTemp}"

    # check if blockchain data is available
    hddBlocksBitcoin=$(ls /mnt/hdd/bitcoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
    echo "hddBlocksBitcoin=${hddBlocksBitcoin}"
    if [ "${blockchainType}" = "bitcoin" ] && [ ${hddBlocksBitcoin} -eq 1 ]; then
      echo "hddGotBlockchain=1"
    elif [ ${#blockchainType} -gt 0 ]; then
      echo "hddGotBlockchain=0"
    fi

    # check size in bytes and GBs
    if [ "${isZFS}" -gt 0 ]; then
      sizeDataPartition=$(zpool list -pH | awk '{print $2}')
      hddGigaBytes=$(echo "scale=0; ${sizeDataPartition}/1024/1024/1024" | bc -l)
    else
      sizeDataPartition=$(lsblk -o NAME,SIZE -b | grep "${hddDataPartition}" | awk '$1=$1' | cut -d " " -f 2)
      hddGigaBytes=$(echo "scale=0; ${sizeDataPartition}/1024/1024/1024" | bc -l)
    fi
    hddBytes=${sizeDataPartition}
    echo "hddBytes=${sizeDataPartition}"
    echo "hddGigaBytes=${hddGigaBytes}"

    # used space - at the moment just string info to display
    if [ "${isBTRFS}" -gt 0 ]; then
      if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
	nvp=""
      else
	nvp="p"
      fi
      # BTRFS calculations
      # TODO: this is the final/correct way - make better later
      # https://askubuntu.com/questions/170044/btrfs-and-missing-free-space
      datadrive=$(df -h | grep "/dev/${hdd}${nvp}1" | sed -e's/  */ /g' | cut -d" " -f 5)
      storageDrive=$(df -h | grep "/dev/${hdd}${nvp}2" | sed -e's/  */ /g' | cut -d" " -f 5)
      hdd_data_free1Kblocks=$(df -h -k /dev/${hdd}${nvp}1 | grep "/dev/${hdd}${nvp}1" | sed -e's/  */ /g' | cut -d" " -f 4 | tr -dc '0-9')
      hddUsedInfo="${datadrive} ${storageDrive}"
    elif [ "${isZFS}" -gt 0 ]; then
      # ZFS calculations
      hdd_used_space=$(($(zpool list -pH | awk '{print $3}')/1024/1024/1024))
      hdd_used_ratio=$((100 * hdd_used_space / hddGigaBytes))
      hdd_data_free1Kblocks=$(($(zpool list -pH | awk '{print $4}') / 1024))
      hddUsedInfo="${hdd_used_ratio}%"
    else
      # EXT4 calculations
      hdd_used_space=$(df -h | grep "/dev/${hddDataPartitionExt4}" | sed -e's/  */ /g' | cut -d" " -f 3  2>/dev/null)
      hdd_used_ratio=$(df -h | grep "/dev/${hddDataPartitionExt4}" | sed -e's/  */ /g' | cut -d" " -f 5 | tr -dc '0-9' 2>/dev/null)
      hdd_data_free1Kblocks=$(df -h -k /dev/${hddDataPartitionExt4} | grep "/dev/${hddDataPartitionExt4}" | sed -e's/  */ /g' | cut -d" " -f 4 | tr -dc '0-9')
      hddUsedInfo="${hdd_used_ratio}%"
    fi

    hddTBSize="<1TB"
    if [ ${hddBytes} -gt 800000000000 ]; then
      hddTBSize="1TB"
    fi
    if [ ${hddBytes} -gt 1800000000000 ]; then
      hddTBSize="2TB"
    fi
    if [ ${hddBytes} -gt 2300000000000 ]; then
      hddTBSize=">2TB"
    fi
    if [ "${hddTemp}" != "" ]; then
      hddUsedInfo="${hdd_used_ratio}% ${hddTemp}°C"
    fi
    echo "hddTBSize='${hddTBSize}'"
    echo "hddUsedInfo='${hddTBSize} ${hddUsedInfo}'"
    hddDataFreeBytes=$((${hdd_data_free1Kblocks} * 1024))
    hddDataFreeGB=$((${hdd_data_free1Kblocks} / (1024 * 1024)))
    echo "hddDataFreeBytes=${hddDataFreeBytes}"
    echo "hddDataFreeKB=${hdd_data_free1Kblocks}"
    echo "hddDataFreeGB=${hddDataFreeGB}"
  fi

  # HDD Adapter UASP support --> https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
  # in both cases (if mounted or not - using the hdd selection from both cases)
  # only check if lsusb command is availabe
  if [ ${#hdd} -gt 0 ] && [ "$(type -t lsusb | grep -c file)" -gt 0 ]; then
    # determine USB HDD adapter model ID 
    hddAdapter=$(lsusb | grep "SATA" | head -1 | cut -d " " -f6)
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "GC Protronics" | head -1 | cut -d " " -f6)
    fi
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "ASMedia Technology" | head -1 | cut -d " " -f6)
    fi
    echo "hddAdapterUSB='${hddAdapter}'"
    hddAdapterUSAP=0
    
    # check if force UASP flag is set on sd card
    if [ -f "${raspi_bootdir}/uasp.force" ]; then
      hddAdapterUSAP=1
    fi
    # or UASP is set by config file
    if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "forceUasp=on") -eq 1 ]; then
      hddAdapterUSAP=1
    fi
    # check if HDD ADAPTER is on UASP WHITELIST (tested devices)
    if [ "${hddAdapter}" == "174c:55aa" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support
      hddAdapterUSAP=1
    fi
    if [ "${hddAdapter}" == "174c:1153" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support, 2021+ version
      hddAdapterUSAP=1
    fi
    if [ "${hddAdapter}" == "0825:0001" ] || [ "${hddAdapter}" == "174c:0825" ]; then
      # SupTronics 2.5" SATA HDD Shield X825 v1.5
      hddAdapterUSAP=1
    fi
    if [ "${hddAdapter}" == "2109:0715" ]; then
      # ICY BOX IB-247-C31 Type-C Enclosure for 2.5inch SATA Drives
      hddAdapterUSAP=1
    fi
    if [ "${hddAdapter}" == "174c:235c" ]; then
      # Cable Matters USB 3.1 Type-C Gen2 External SATA SSD Enclosure
      hddAdapterUSAP=1
    fi
    echo "hddAdapterUSAP=${hddAdapterUSAP}"
  fi
  echo
  echo "# RAID"
  echo "isRaid=${isRaid}"
  if [ ${isRaid} -eq 1 ] && [ ${isMounted} -eq 1 ] && [ ${isBTRFS} -eq 1 ]; then
    # RAID is ON - give information about running raid setup
    # show devices used for raid
    raidHddDev=$(lsblk -o NAME,MOUNTPOINT | grep "/mnt/hdd" | awk '$1=$1' | cut -d " " -f 1 | sed 's/[^0-9a-z]*//g')
    raidUsbDev=$(btrfs filesystem show /mnt/hdd | grep -F -v "${raidHddDev}" | grep "/dev/" | cut -d "/" --f 3)
    echo "raidHddDev='${raidHddDev}'"
    echo "raidUsbDev='${raidUsbDev}'"
  else
    # RAID is OFF - give information about possible drives to activate
    # find the possible drives that can be used as 
    drivecounter=0
    for disk in $(lsblk -o NAME,TYPE | grep "disk" | awk '$1=$1' | cut -d " " -f 1)
    do
      devMounted=$(lsblk -o MOUNTPOINT,NAME | grep "$disk" | grep -c "^/")
      # is raid candidate when not mounted and not the data drive candidate (hdd/ssd)
      if [ ${devMounted} -eq 0 ] && [ "${disk}" != "${hdd}" ] && [ "${hdd}" != "" ] && [ "${disk}" != "" ] && [ "${disk}" != "zram0" ]; then
        sizeBytes=$(lsblk -o NAME,SIZE -b | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2)
        sizeGigaBytes=$(echo "scale=0; ${sizeBytes}/1024/1024/1024" | bc -l)
        vedorname=$(lsblk -o NAME,VENDOR | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2 | sed 's/[^a-zA-Z0-9]//g')
        mountoption="${disk} ${sizeGigaBytes} GB ${vedorname}"
        echo "raidCandidate[${drivecounter}]='${mountoption}'"
        drivecounter=$(($drivecounter +1))
      fi
    done
    echo "raidCandidates=${drivecounter}"
  fi
  echo
  echo "# SWAP"
  echo "isSwapExternal=${isSwapExternal}"
  if [ ${isSwapExternal} -eq 1 ]; then
    echo "SwapExternalPath='${externalSwapPath}'"
  fi
  echo
  exit 1
fi

######################
# FORMAT EXT4 or BTRFS
######################

# check basics for formatting
if [ "$1" = "format" ]; then
  # check valid format
  if [ "$2" = "btrfs" ]; then
    >&2 echo "# DATA DRIVE - FORMATTING to BTRFS layout (new)"
    # check if btrfs-tools are installed
    apt-get install -y btrfs-progs 1>/dev/null
  elif [ "$2" = "ext4" ]; then
    >&2 echo "# DATA DRIVE - FORMATTING to EXT4 layout (old)"
  else
    >&2 echo "# missing valid second parameter: 'btrfs' or 'ext4'"
    echo "error='missing parameter'"
    exit 1
  fi
  
  # get device name to format
  hdd=$3
  if [ ${#hdd} -eq 0 ]; then
    >&2 echo "# missing valid third parameter as the device (like 'sda')"
    >&2 echo "# run 'status' to see candidate devices"
    echo "error='missing parameter'"
    exit 1
  fi
  if [ "$2" = "btrfs" ]; then
     # check if device is existing and a disk (not a partition)
     isValid=$(lsblk -o NAME,TYPE | grep disk | grep -c "${hdd}")
  else
     # check if device is existing (its OK when its a partition)
     isValid=$(lsblk -o NAME,TYPE | grep -c "${hdd}")
  fi
  if [ ${isValid} -eq 0 ]; then
    >&2 echo "# given device was not found"
    >&2 echo "# or is not of type disk - see 'lsblk'"
    echo "error='device not valid'"
    exit 1
  fi

  # get basic info on data drive 
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  if [ ${isSwapExternal} -eq 1 ] && [ "${hdd}" == "${datadisk}" ]; then
    >&2 echo "# Switching off external SWAP of system drive"
    dphys-swapfile swapoff 1>/dev/null
    dphys-swapfile uninstall 1>/dev/null
  fi
  >&2 echo "# Unmounting all partitions of this device"
  # remove device from all system mounts (also fstab)
  lsblk -o UUID,NAME | grep "${hdd}" | cut -d " " -f 1 | grep "-" | while read -r uuid ; do
    if [ ${#uuid} -gt 0 ]; then
      >&2 echo "# Cleaning /etc/fstab from ${uuid}"
      sed -i "/UUID=${uuid}/d" /etc/fstab
      sync
    else
      >&2 echo "# skipping empty result"
    fi
  done
  mount -a
  if [ "${hdd}" == "${datadisk}" ]; then
    >&2 echo "# Make sure system drives are unmounted .."
    umount /mnt/hdd 2>/dev/null
    umount /mnt/temp 2>/dev/null
    umount /mnt/storage 2>/dev/null
    unmounted1=$(df | grep -c "/mnt/hdd")
    if [ ${unmounted1} -gt 0 ]; then
      >&2 echo "# ERROR: failed to unmount /mnt/hdd"
      echo "error='failed to unmount /mnt/hdd'"
      exit 1
    fi
    unmounted2=$(df | grep -c "/mnt/temp")
    if [ ${unmounted2} -gt 0 ]; then
      >&2 echo "# ERROR: failed to unmount /mnt/temp"
      echo "error='failed to unmount /mnt/temp'"
      exit 1
    fi
    unmounted3=$(df | grep -c "/mnt/storage")
    if [ ${unmounted3} -gt 0 ]; then
      >&2 echo "# ERROR: failed to unmount /mnt/storage"
      echo "error='failed to unmount /mnt/storage'"
      exit 1
    fi
  fi
  
  if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
    if [[ $hdd =~ [0-9] ]]; then
      ext4IsPartition=1
    else
      ext4IsPartition=0
    fi
  else
    if [[ $hdd =~ [p] ]]; then
      ext4IsPartition=1
    else
      ext4IsPartition=0
    fi
  fi
  wipePartitions=0
  if [ "$2" = "btrfs" ]; then
     wipePartitions=1
  fi
  if [ "$2" = "ext4" ] && [ $ext4IsPartition -eq 0 ]; then
     wipePartitions=1
  fi
  if [ $wipePartitions -eq 1 ]; then
     # wipe all partitions and write fresh GPT
     >&2 echo "# Wiping all partitions (sfdisk/wipefs)"
     >&2 echo "# sfdisk"
     sfdisk --delete /dev/${hdd}
     sleep 4
     >&2 echo "# wipefs"
     wipefs -a /dev/${hdd}
     sleep 4
     >&2 echo "# lsblk"
     partitions=$(lsblk | grep -c "─${hdd}")
     if [ ${partitions} -gt 0 ]; then
       >&2 echo "# WARNING: partitions are still not clean - try Quick & Dirty"
       dd if=/dev/zero of=/dev/${hdd} bs=512 count=1
     fi
     partitions=$(lsblk | grep -c "─${hdd}")
     if [ ${partitions} -gt 0 ]; then
       >&2 echo "# ERROR: partition cleaning failed"
       echo "error='partition cleaning failed'"
       exit 1
     fi
     >&2 echo "# parted"
     parted -s /dev/${hdd} mklabel gpt 1>/dev/null 1>&2
     sleep 2
     sync
  fi

  # formatting old: EXT4
  if [ "$2" = "ext4" ]; then
     if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
       nvp=""
     else
       nvp="p"
     fi
     # prepare temp mount point
     mkdir -p /tmp/ext4 1>/dev/null
     if [ $ext4IsPartition -eq 0 ]; then
        # write new EXT4 partition
        >&2 echo "# Creating the one big partition - hdd(${hdd})"
        parted -s /dev/${hdd} mkpart primary ext4 0% 100% 1>&2
        sleep 6
        >&2 echo "# sync"
        sync
        # loop until the partition gets available
        loopdone=0
        loopcount=0
        while [ ${loopdone} -eq 0 ]
        do
          >&2 echo "# waiting until the partition gets available"
          sleep 2
          sync
          loopdone=$(lsblk -o NAME | grep -c ${hdd}${nvp}1)
          loopcount=$(($loopcount +1))
          if [ ${loopcount} -gt 10 ]; then
            >&2 echo "# partition failed"
            echo "error='partition failed'"
            exit 1
          fi
        done
        >&2 echo "# partition available"
     fi

     # make sure /mnt/hdd is unmounted before formatting
     umount -f /tmp/ext4 2>/dev/null
     unmounted=$(df | grep -c "/tmp/ext4")
     if [ ${unmounted} -gt 0 ]; then
       >&2 echo "# ERROR: failed to unmount /tmp/ext4"
       echo "error='failed to unmount /tmp/ext4'"
       exit 1
     fi
     >&2 echo "# Formatting"
     if [ $ext4IsPartition -eq 0 ]; then
        mkfs.ext4 -F -L BLOCKCHAIN /dev/${hdd}${nvp}1 1>/dev/null
     else
        mkfs.ext4 -F -L BLOCKCHAIN /dev/${hdd} 1>/dev/null
     fi
     loopdone=0
     loopcount=0
     while [ ${loopdone} -eq 0 ]
     do
       >&2 echo "# waiting until formatted drives gets available"
       sleep 2
       sync
       loopdone=$(lsblk -o NAME,LABEL | grep -c BLOCKCHAIN)
       loopcount=$(($loopcount +1))
       if [ ${loopcount} -gt 10 ]; then
         >&2 echo "# ERROR: formatting ext4 failed"
         echo "error='formatting ext4 failed'"
         exit 1
       fi
     done

     # setting fsk check interval to 1
     # see https://github.com/rootzoll/raspiblitz/issues/360#issuecomment-467567572
     if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
       nvp=""
     else
       nvp="p"
     fi
     if [ $ext4IsPartition -eq 0 ]; then
       tune2fs -c 1 /dev/${hdd}${nvp}1
     else
       tune2fs -c 1 /dev/${hdd}
     fi
     >&2 echo "# OK EXT 4 format done"
     exit 0
  fi

  # formatting new: BTRFS layout - this consists of 3 volumes:
  if [ "$2" = "btrfs" ]; then
    if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
      nvp=""
    else
      nvp="p"
    fi
    # prepare temp mount point
    mkdir -p /tmp/btrfs 1>/dev/null
    >&2 echo "# Creating BLITZDATA (${hdd})"
    parted -s -- /dev/${hdd} mkpart primary btrfs 1024KiB 30GiB 1>/dev/null
    sync
    sleep 6
    win=$(lsblk -o NAME | grep -c ${hdd}${nvp}1)
    if [ ${win} -eq 0 ]; then 
      echo "error='partition failed'"
      exit 1
    fi
    mkfs.btrfs -f -L BLITZDATA /dev/${hdd}${nvp}1 1>/dev/null
    # check result
    loopdone=0
    loopcount=0
    while [ ${loopdone} -eq 0 ]
    do
      >&2 echo "# waiting until formatted drives gets available"
      sleep 2
      sync
      parted -l
      loopdone=$(lsblk -o NAME,LABEL | grep -c BLITZDATA)
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 60 ]; then
        >&2 echo "# ERROR: formatting BTRFS failed (BLITZDATA)"
        >&2 echo "# check with: lsblk -o NAME,LABEL | grep -c BLITZDATA"
        echo "error='formatting failed'"
        exit 1
      fi
    done
    >&2 echo "# OK BLITZDATA exists now"
    >&2 echo "# Creating SubVolume for Snapshots"
    mount /dev/${hdd}${nvp}1 /tmp/btrfs 1>/dev/null
    if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
      echo "error='mount ${hdd}${nvp}1 failed'"
      exit 1
    fi
    cd /tmp/btrfs
    btrfs subvolume create WORKINGDIR
    subVolDATA=$(btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
    cd && umount /tmp/btrfs
    >&2 echo "# Creating BLITZSTORAGE"
    parted -s -- /dev/${hdd} mkpart primary btrfs 30GiB -34GiB 1>/dev/null
    sync
    sleep 6
    win=$(lsblk -o NAME | grep -c ${hdd}${nvp}2)
    if [ ${win} -eq 0 ]; then 
      echo "error='partition failed'"
      exit 1
    fi
    mkfs.btrfs -f -L BLITZSTORAGE /dev/${hdd}${nvp}2 1>/dev/null
    # check result
    loopdone=0
    loopcount=0
    while [ ${loopdone} -eq 0 ]
    do
      >&2 echo "# waiting until formatted drives gets available"
      sleep 2
      sync
      parted -l
      loopdone=$(lsblk -o NAME,LABEL | grep -c BLITZSTORAGE)
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 60 ]; then
        >&2 echo "# ERROR: formatting BTRFS failed (BLITZSTORAGE)"
        echo "error='formatting failed'"
        exit 1
      fi
    done
    >&2 echo "# OK BLITZSTORAGE exists now"
    >&2 echo "# Creating SubVolume for Snapshots"
    mount /dev/${hdd}${nvp}2 /tmp/btrfs 1>/dev/null
    if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
      echo "error='mount ${hdd}${nvp}2 failed'"
      exit 1
    fi
    cd /tmp/btrfs
    btrfs subvolume create WORKINGDIR
    cd && umount /tmp/btrfs
    >&2 echo "# Creating the FAT32 partition"
    parted -s -- /dev/${hdd} mkpart primary fat32 -34GiB 100% 1>/dev/null
    sync && sleep 3
    win=$(lsblk -o NAME | grep -c ${hdd}${nvp}3)
    if [ ${win} -eq 0 ]; then 
      echo "error='partition failed'"
      exit 1
    fi
    >&2 echo "# Creating Volume BLITZTEMP (format)"
    mkfs -t vfat -n BLITZTEMP /dev/${hdd}${nvp}3 1>/dev/null
    # check result
    loopdone=0
    loopcount=0
    while [ ${loopdone} -eq 0 ]
    do
      >&2 echo "# waiting until formatted drives gets available"
      sleep 2
      sync
      parted -l
      loopdone=$(lsblk -o NAME,LABEL | grep -c BLITZTEMP)
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 60 ]; then
        >&2 echo "# ERROR: formatting vfat failed (BLITZTEMP)"
        echo "error='formatting failed'"
        exit 1
      fi
    done
    >&2 echo "# OK BLITZTEMP exists now"
    >&2 echo "# OK BTRFS format done"
    exit 0
  fi
fi

########################################
# Refresh FSTAB for permanent mount
########################################

if [ "$1" = "fstab" ]; then  
  # get device to temp mount
  hdd=$2
  if [ ${#hdd} -eq 0 ]; then
    echo "# FAIL which device/partition should be temp mounted (e.g. sda)"
    echo "# run 'status' to see device candidates"
    echo "error='missing second parameter'"
    exit 1
  fi
  # check if exist and which format
  # if hdd is a partition (ext4)
  if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
    if [[ $hdd =~ [0-9] ]]; then
      # ext4
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hdd} | cut -d ' ' -f 1)
    else
      # btrfs
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hdd}1 | cut -d ' ' -f 1)
    fi
  else
    if [[ $hdd =~ [p] ]]; then
      # ext4
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hdd} | cut -d ' ' -f 1)
    else
      # btrfs
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hdd}p1 | cut -d ' ' -f 1)
    fi
  fi
  if [ ${#hddFormat} -eq 0 ]; then
    echo "# FAIL given device/partition not found"
    echo "error='device not found'"
    exit 1
  fi
  # unmount
  if [ ${isMounted} -eq 1 ]; then
    echo "# unmounting all drives"
    umount /mnt/hdd > /dev/null 2>&1
    umount /mnt/storage > /dev/null 2>&1
    umount /mnt/temp > /dev/null 2>&1
  fi

  if [ "${hddFormat}" = "ext4" ]; then

    ### EXT4 ###

    hddDataPartitionExt4=$hdd
    # loop until the uuids are available
    uuid1=""
    loopcount=0
    while [ ${#uuid1} -eq 0 ]
    do
      echo "# waiting until uuid gets available"
      sleep 2
      sync
      uuid1=$(lsblk -o NAME,UUID | grep "${hddDataPartitionExt4}" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 10 ]; then
        echo "error='no uuid'"
        exit 1
      fi
    done

    # write new /etc/fstab & mount
    echo "# mount /mnt/hdd"
    mkdir -p /mnt/hdd 1>/dev/null
    updated=$(cat /etc/fstab | grep -c "/mnt/hdd")
    if [ $updated -eq 0 ]; then
       echo "# updating /etc/fstab"
       sed "/raspiblitz/ i UUID=${uuid1} /mnt/hdd ext4 noexec,defaults 0 2" -i /etc/fstab 1>/dev/null
    fi
    sync
    mount -a 1>/dev/null

    # loop mounts are available
    mountactive1=0
    loopcount=0
    while [ ${mountactive1} -eq 0 ]
    do
      echo "# waiting until mounting is active"
      sleep 2
      sync
      mountactive1=$(df | grep -c /mnt/hdd)
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 10 ]; then
        echo "# WARNING was not able freshly mount new devices - might need reboot or check /etc/fstab"
        echo "needsReboot=1"
        exit 0
      fi
    done
    echo "# OK - fstab updated for EXT4 layout"
    exit 1

  elif [ "${hddFormat}" = "btrfs" ]; then

    ### BTRFS ###
    
    >&2 echo "# BTRFS: Updating /etc/fstab & mount"
    # get info on: Data Drive
    uuidDATA=$(lsblk -o UUID,NAME,LABEL | grep "${hdd}" | grep "BLITZDATA" | cut -d " " -f 1 | grep "-")
    mkdir -p /tmp/btrfs
    if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
      nvp=""
    else
      nvp="p"
    fi
    mount /dev/${hdd}${nvp}1 /tmp/btrfs 1>/dev/null
    if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
      echo "error='mount ${hdd}${nvp}1 failed'"
      exit 1
    fi
    cd /tmp/btrfs
    subVolDATA=$(btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
    cd && umount /tmp/btrfs
    echo "uuidDATA='${uuidDATA}'"
    echo "subVolDATA='${subVolDATA}'"
    if [ ${#uuidDATA} -eq 0 ] || [ ${#subVolDATA} -eq 0 ]; then
      echo "error='no datadrive uuids'"
      exit 1
    fi
  
    # get info on: Storage Drive
    uuidSTORAGE=$(lsblk -o UUID,NAME,LABEL | grep "${hdd}" | grep "BLITZSTORAGE" | cut -d " " -f 1 | grep "-")
    mount /dev/${hdd}${nvp}2 /tmp/btrfs 1>/dev/null
    if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
      echo "error='mount ${hdd}${nvp}2 failed'"
      exit 1
    fi
    cd /tmp/btrfs
    subVolSTORAGE=$(btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
    cd && umount /tmp/btrfs
    echo "uuidSTORAGE='${uuidSTORAGE}'"
    echo "subVolSTORAGE='${subVolSTORAGE}'"
    if [ ${#uuidSTORAGE} -eq 0 ] || [ ${#subVolSTORAGE} -eq 0 ]; then
      echo "error='no storagedrive uuids'"
      exit 1
    fi

    # get info on: Temp Drive
    uuidTEMP=$(lsblk -o LABEL,UUID | grep "BLITZTEMP" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
    echo "uuidTEMP='${uuidTEMP}'"
    if [ ${#uuidTEMP} -eq 0 ]; then
      echo "error='no tempdrive uuids'"
      exit 1
    fi

    # remove old entries from fstab
    lsblk -o UUID,NAME | grep "${hdd}" | cut -d " " -f 1 | grep "-" | while read -r uuid ; do
      >&2 echo "# Cleaning /etc/fstab from ${uuid}"
      sed -i "/UUID=${uuid}/d" /etc/fstab
      sync
    done

    # get user and groupid if usr/group bitcoin
    bitcoinUID=$(id -u bitcoin)
    bitcoinGID=$(id -g bitcoin)

    # modifying /etc/fstab & mount
    mkdir -p /mnt/hdd 1>/dev/null
    fstabAdd1="UUID=${uuidDATA} /mnt/hdd btrfs noexec,defaults,subvolid=${subVolDATA} 0 2"
    sed "3 a ${fstabAdd1}" -i /etc/fstab 1>/dev/null
    mkdir -p /mnt/storage 1>/dev/null
    fstabAdd2="UUID=${uuidSTORAGE} /mnt/storage btrfs noexec,defaults,subvolid=${subVolSTORAGE} 0 2"
    sed "4 a ${fstabAdd2}" -i /etc/fstab 1>/dev/null  
    mkdir -p /mnt/temp 1>/dev/null
    fstabAdd3="UUID=${uuidTEMP} /mnt/temp vfat noexec,defaults,uid=${bitcoinUID},gid=${bitcoinGID} 0 2"
    sed "5 a ${fstabAdd3}" -i /etc/fstab 1>/dev/null
    sync && mount -a 1>/dev/null

    # test mount
    mountactive1=0
    mountactive2=0
    mountactive3=0
    loopcount=0
    while [ ${mountactive1} -eq 0 ] || [ ${mountactive2} -eq 0 ] || [ ${mountactive3} -eq 0 ]
    do
      >&2 echo "# waiting until mountings are active"
      sleep 2
      sync
      mountactive1=$(df | grep -c /mnt/hdd)
      mountactive2=$(df | grep -c /mnt/temp)
      mountactive3=$(df | grep -c /mnt/storage)  
      loopcount=$(($loopcount +1))
      if [ ${loopcount} -gt 10 ]; then
        >&2 echo "# WARNING was not able freshly mount new devices - might need reboot or check /etc/fstab"
        echo "needsReboot=1"
        exit 1
      fi
    done

    >&2 echo "# OK - fstab updated for BTRFS layout"
    exit 1

  else
    echo "error='wrong hdd format'"
    exit 1
  fi
fi

########################################
# RAID with USB Stick for data partition
########################################

if [ "$1" = "raid" ]; then

  # checking if BTRFS mode
  if [ ${isBTRFS} -eq 0 ]; then
    echo "error='raid only BTRFS'"
    exit 1
  fi

  # checking parameter
  if [ "$2" = "on" ]; then
    if [ ${isRaid} -eq 1 ]; then
      >&2 echo "# OK - already ON"
      exit
    fi
    >&2 echo "# RAID - Adding raid drive to RaspiBlitz data drive"
  elif [ "$2" = "off" ]; then
    >&2 echo "# RAID - Removing raid drive to RaspiBlitz data drive"  
  else
    >&2 echo "# possible 2nd parameter is 'on' or 'off'"  
    echo "error='unknown parameter'"
    exit 1
  fi
fi

# RAID --> ON
if [ "$1" = "raid" ] && [ "$2" = "on" ]; then

  # todo - how to determine which device is the usb raid to add
  # maybe give all options with "status" and have this as
  # second parameter - like its named: lsblk
  usbdev=$3
  if [ ${#usbdev} -eq 0 ]; then
    >&2 echo "# FAIL third parameter is missing with the name of the USB device to add"
    echo "error='missing parameter'"
    exit 1
  fi
  
  # check that dev exists and is unique
  usbdevexists=$(lsblk -o NAME,UUID | grep -c "^${usbdev}")
  if [ ${usbdevexists} -eq 0 ]; then
    >&2 echo "# FAIL not found: ${usbdev}"
    echo "error='dev not found'"
    exit 1
  fi
  if [ ${usbdevexists} -gt 1 ]; then
    >&2 echo "# FAIL multiple matches: ${usbdev}"
    echo "error='dev not unique'"
    exit 1
  fi

  # check that device is a disk and not a partition
  isDisk=$(lsblk -o NAME,TYPE | grep "^${usbdev}" | grep -c disk)
  if [ ${isDisk} -eq 0 ]; then
    echo "error='dev is not disk'"
    exit 1
  fi

  # check that device is not mounted
  if [ $(df | cut -d " " -f 1 | grep -c "/${usbdev}") -gt 0 ]; then
    echo "error='dev is in use'"
    exit 1
  fi

  # check if old BTRFS filesystem
  usbdevBTRFS=$(lsblk -o NAME,UUID,FSTYPE | grep "^${usbdev}" | grep -c "btrfs")
  if [ ${usbdevBTRFS} -eq 1 ]; then
    # edge case: already contains BTRFS data
    # TODO: once implemented -> also make sure that dev1 is named "DATASTORE" and if 2nd is other -> format and add as raid
    >&2 echo "# ERROR: # NOT IMPLEMENTED YET -> devices seem contain old data"
    >&2 echo "# if you dont care about that data: format on other computer with FAT"
    echo "error='old data on dev'"
    exit 1
  fi

  # remove all partitions from device
  for v_partition in $(parted -s /dev/${usbdev} print|awk '/^ / {print $1}')
  do
    parted -s /dev/${usbdev} rm ${v_partition}
  done

  # check if usb device is at least 30GB big
  usbdevsize=$(lsblk -o NAME,SIZE -b | grep "^${usbdev}" | awk '$1=$1' | cut -d " " -f 2)
  if [ ${usbdevsize} -lt 30000000000 ]; then
    >&2 echo "# FAIL ${usbdev} is smaller than the minimum 30GB"
    echo "error='dev too small'"
    exit 1
  fi

  # add usb device as raid for data
  >&2 echo "# adding ${usbdev} as BTRFS raid1 for /mnt/hdd"
  btrfs device add -f /dev/${usbdev} /mnt/hdd 1>/dev/null
  btrfs filesystem balance start -dconvert=raid1 -mconvert=raid1 /mnt/hdd 1>/dev/null
  >&2 echo "# OK - ${usbdev} is now part of a RAID1 for your RaspiBlitz data"
  exit 0
fi

# RAID --> OFF
if [ "$1" = "raid" ] && [ "$2" = "off" ]; then
 
  # checking if BTRFS mode
  isBTRFS=$(btrfs filesystem show 2>/dev/null| grep -c 'BLITZSTORAGE')
  if [ ${isBTRFS} -eq 0 ]; then
    echo "error='raid only BTRFS'"
    exit 1
  fi

  deviceToBeRemoved="/dev/${raidUsbDev}"
  # just in case be able to remove missing drive
  if [ ${#raidUsbDev} -eq 0 ]; then
    deviceToBeRemoved="missing"
  fi

  >&2 echo "# removing USB DEV from RAID"
  btrfs balance start -mconvert=dup -dconvert=single /mnt/hdd 1>/dev/null
  btrfs device remove ${deviceToBeRemoved} /mnt/hdd 1>/dev/null
  
  isRaid=$(btrfs filesystem df /mnt/hdd 2>/dev/null | grep -c "Data, RAID1")
  if [ ${isRaid} -eq 0 ]; then
    >&2 echo "# OK - RaspiBlitz data is not running in RAID1 anymore"
    exit 0
  else
    >&2 echo "# FAIL - was not able to remove RAID device"
    echo "error='fail'"
    exit 1
  fi
fi

########################################
# SNAPSHOTS - make and replay
########################################

if [ "$1" = "snapshot" ]; then

  # check if data drive is mounted
  if [ ${isMounted} -eq 0 ]; then
    echo "error='no data drive mounted'"
    exit 1
  fi

  # check if BTRFS
  if [ ${isBTRFS} -eq 0 ]; then
    echo "error='no BTRFS'"
    exit 1
  fi

  # SECOND PARAMETER: 'data' or 'storage'
  if [ "$2" = "data" ]; then
    subvolume="/mnt/hdd"
    subvolumeESC="\/mnt\/hdd"
    uuid=$(lsblk -o LABEL,UUID | grep "BLITZDATA" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
  elif [ "$2" = "storage" ]; then
    subvolume="/mnt/storage"
    subvolumeESC="\/mnt\/storage"
    uuid=$(lsblk -o LABEL,UUID | grep "BLITZSTORAGE" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
  else
    >&2 echo "# second parameter needs to be 'data' or 'storage'"
    echo "error='unknown parameter'"
    exit 1
  fi
  >&2 echo "# RASPIBLITZ SNAPSHOTS"
  partition=$(df | grep "${subvolume}" | cut -d " " -f 1)
  echo "subvolume='${subvolume}'"
  echo "partition='${partition}'"
  if [ "$3" = "create" ]; then
    >&2 echo "# Preparing Snapshot ..."
    # make sure backup folder exists
    mkdir -p ${subvolume}/snapshots
    # delete old backup if existing
    oldBackupExists=$(ls ${subvolume}/snapshots | grep -c backup)
    if [ ${oldBackupExists} -gt 0 ]; then
      >&2 echo "# Deleting old snapshot"
      btrfs subvolume delete ${subvolume}/snapshots/backup 1>/dev/null
    fi
    >&2 echo "# Creating Snapshot ..."
    btrfs subvolume snapshot ${subvolume} ${subvolume}/snapshots/backup 1>/dev/null
    if [ $(btrfs subvolume list ${subvolume} | grep -c snapshots/backup) -eq 0 ]; then
      echo "error='not created'"
      exit 1
    else
      >&2 echo "# OK - Snapshot created"
      exit 0
    fi
  elif [ "$3" = "rollback" ]; then
    # check if an old snapshot exists
    oldBackupExists=$(ls ${subvolume}/snapshots | grep -c backup)
    if [ ${oldBackupExists} -eq 0 ]; then
      echo "error='no old snapshot found'"
      exit 1
    fi
    >&2 echo "# Resetting state to old Snapshot ..."
    umount ${subvolume}
    mkdir -p /tmp/btrfs 1>/dev/null
    mount ${partition} /tmp/btrfs
    mv /tmp/btrfs/WORKINGDIR/snapshots/backup /tmp/btrfs/backup
    btrfs subvolume delete /tmp/btrfs/WORKINGDIR
    mv /tmp/btrfs/backup /tmp/btrfs/WORKINGDIR
    subVolID=$(btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
    sed -i "/${subvolumeESC}/d" /etc/fstab
    fstabAdd="UUID=${uuid} ${subvolume} btrfs noexec,defaults,subvolid=${subVolID} 0 2"
    sed "4 a ${fstabAdd}" -i /etc/fstab 1>/dev/null  
    umount /tmp/btrfs
    mount -a
    sync
    if [ $(df | grep -c "${subvolume}") -eq 0 ]; then
      >&2 echo "# check drive setting ... rollback seemed to "
      echo "error='failed rollback'"
      exit 1
    fi
    echo "OK - Rollback done"
    exit 0
  else
    >&2 echo "# third parameter needs to be 'create' or 'rollback'"
    echo "error='unknown parameter'"
    exit 1 
  fi
fi

###################
# TEMP MOUNT
###################

if [ "$1" = "tempmount" ]; then

  # get HDD status and candidates
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)

  if [ ${isMounted} -eq 1 ]; then
    echo "error='already mounted'"
    exit 1
  fi

  # get device to temp mount from parameter (optional)
  hdd=$2
  # automount if no parameter the hddcandinate
  if [ "${hdd}" == "" ]; then
    if [ "${hddFormat}" != "btrfs" ]; then
      hdd="${hddPartitionCandidate}"
    else
      hdd="${hddCandidate}"
    fi
  fi
  # if still no hdd .. throw error
  if [ "${hdd}" == "" ]; then
    >&2 echo "# FAIL there is no detected hdd candidate to tempmount"
    echo "error='hdd not found'"
    exit 1
  fi

  # if hdd is a partition
  if [ $(echo "${hdd}" | grep -c "nvme")  = 0 ]; then
    if [[ $hdd =~ [0-9] ]]; then
      hddDataPartition=$hdd
      hddDataPartitionExt4=$hddDataPartition
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hddDataPartitionExt4} | cut -d ' ' -f 1)
    else
      hddBTRFS=$hdd
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hddBTRFS}1 | cut -d ' ' -f 1)
    fi
  else
    if [[ $hdd =~ [p] ]]; then
      hddDataPartition=$hdd
      hddDataPartitionExt4=$hddDataPartition
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hddDataPartitionExt4} | cut -d ' ' -f 1)
    else
      hddBTRFS=$hdd
      hddFormat=$(lsblk -o FSTYPE,NAME | grep ${hddBTRFS}p1 | cut -d ' ' -f 1)
    fi
  fi
  if [ ${#hddFormat} -eq 0 ]; then
    >&2 echo "# FAIL given device not found"
    echo "error='device not found'"
    exit 1
  fi

  if [ "${hddFormat}" == "ext4" ]; then
    if [ "${hddDataPartitionExt4}" == "" ]; then
      echo "error='parameter is no partition'"
      exit 1
    fi
    
    # do EXT4 temp mount
    echo "# temp mount /dev/${hddDataPartitionExt4} --> /mnt/hdd"
    mkdir -p /mnt/hdd 1>/dev/null
    mount /dev/${hddDataPartitionExt4} /mnt/hdd
    # check result
    isMounted=$(df | grep -c "/mnt/hdd")
    if [ ${isMounted} -eq 0 ]; then
      echo "error='temp mount failed'"
      exit 1
    else
      isMounted=1
      isBTRFS=0
    fi
    
  elif [ "${hddFormat}" == "btrfs" ]; then

    # get user and groupid if usr/group bitcoin
    bitcoinUID=$(id -u bitcoin)
    bitcoinGID=$(id -g bitcoin)

    # do BTRFS temp mount
	if [ $(echo "${hddBTRFS}" | grep -c "nvme")  = 0 ]; then
      nvp=""
    else
      nvp="p"
    fi
    mkdir -p /mnt/hdd 1>/dev/null
    mkdir -p /mnt/storage 1>/dev/null
    mkdir -p /mnt/temp 1>/dev/null
    mount -t btrfs -o degraded -o subvol=WORKINGDIR /dev/${hddBTRFS}${nvp}1 /mnt/hdd
    mount -t btrfs -o subvol=WORKINGDIR /dev/${hddBTRFS}${nvp}2 /mnt/storage
    mount -o umask=0000,uid=${bitcoinUID},gid=${bitcoinGID} /dev/${hddBTRFS}${nvp}3 /mnt/temp 

    # check result
    isMountedA=$(df | grep -c "/mnt/hdd")
    isMountedB=$(df | grep -c "/mnt/storage")
    isMountedC=$(df | grep -c "/mnt/temp")
    if [ ${isMountedA} -eq 0 ] && [ ${isMountedB} -eq 0 ] && [ ${isMountedC} -eq 0 ]; then
      echo "error='temp mount failed'"
      exit 1
    else
      isMounted=1
      isBTRFS=1
    fi

  else
    echo "error='no supported hdd format'"
    exit 1
  fi

  # outputting change state
  echo "isMounted=${isMounted}"
  echo "isBTRFS=${isBTRFS}"
  exit 1
fi

if [ "$1" = "unmount" ]; then
  umount /mnt/hdd 2>/dev/null
  umount /mnt/storage 2>/dev/null
  umount /mnt/temp 2>/dev/null
  echo "# OK done unmount"
  exit 1 
fi

########################################
# LINKING all directories with ln
########################################

if [ "$1" = "link" ]; then
  if [ ${isMounted} -eq 0 ] ; then
    echo "error='no data drive mounted'"
    exit 1
  fi

  # cleanups
  if [ $(ls -la /home/bitcoin/ | grep -c "bitcoin ->") -eq 0 ]; then
    >&2 echo "# - /home/bitcoin/.bitcoin -> is not a link, cleaning"
    rm -r /home/bitcoin/.bitcoin 2>/dev/null
  else
    rm /home/bitcoin/.bitcoin 2>/dev/null
  fi

  # make sure common base directory exits
  mkdir -p /mnt/hdd/lnd
  mkdir -p /mnt/hdd/app-data

  if [ ${isBTRFS} -eq 1 ]; then
    >&2 echo "# Creating BTRFS setup links"
    >&2 echo "# - linking blockchains into /mnt/hdd"
    if [ $(ls -F /mnt/hdd/bitcoin | grep -c '/mnt/hdd/bitcoin@') -eq 0 ]; then
      mkdir -p /mnt/storage/bitcoin
      cp -R /mnt/hdd/bitcoin/* /mnt/storage/bitcoin 2>/dev/null
      chown -R bitcoin:bitcoin /mnt/storage/bitcoin
      rm -r /mnt/hdd/bitcoin
      ln -s /mnt/storage/bitcoin /mnt/hdd/bitcoin
      rm /mnt/storage/bitcoin/bitcoin 2>/dev/null
    fi
    >&2 echo "# linking lnd for user bitcoin"
    rm /home/bitcoin/.lnd 2>/dev/null
    ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
    >&2 echo "# - linking blockchain for user bitcoin"
    ln -s /mnt/storage/bitcoin /home/bitcoin/.bitcoin
    >&2 echo "# - linking storage into /mnt/hdd"
    mkdir -p /mnt/storage/app-storage
    chown -R bitcoin:bitcoin /mnt/storage/app-storage
    rm /mnt/hdd/app-storage 2>/dev/null
    ln -s /mnt/storage/app-storage /mnt/hdd/app-storage
    >&2 echo "# - linking temp into /mnt/hdd"
    rm /mnt/hdd/temp 2>/dev/null
    ln -s /mnt/temp /mnt/hdd/temp
    chown -R bitcoin:bitcoin /mnt/temp
    >&2 echo "# - creating snapshots folder"
    mkdir -p /mnt/hdd/snapshots
    mkdir -p /mnt/storage/snapshots
  else
    >&2 echo "# Creating EXT4 setup links"
    >&2 echo "# opening blockchain into /mnt/hdd"
    mkdir -p /mnt/hdd/bitcoin
    >&2 echo "# linking blockchain for user bitcoin"
    rm /home/bitcoin/.bitcoin 2>/dev/null
    ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin
    >&2 echo "# linking lnd for user bitcoin"
    rm /home/bitcoin/.lnd 2>/dev/null
    ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
    >&2 echo "# creating default storage & temp folders"
    mkdir -p /mnt/hdd/app-storage
    mkdir -p /mnt/hdd/temp
  fi

  # fix ownership of linked files
  chown -R bitcoin:bitcoin /mnt/hdd/bitcoin
  chown -R bitcoin:bitcoin /mnt/hdd/lnd
  chown -R bitcoin:bitcoin /home/bitcoin/.lnd
  chown -R bitcoin:bitcoin /home/bitcoin/.bitcoin
  chown bitcoin:bitcoin /mnt/hdd/app-storage
  chown bitcoin:bitcoin /mnt/hdd/app-data
  chown -R bitcoin:bitcoin /mnt/hdd/temp 2>/dev/null
  chmod -R 777 /mnt/temp 2>/dev/null
  chmod -R 777 /mnt/hdd/temp 2>/dev/null

  # write info files about what directories are for

  echo "The /mnt/hdd/temp directory is for short time data and will get cleaned up on very start. Dont work with data here thats bigger then 25GB - because on BTRFS hdd layout this is a own partition with limited space. Also on BTRFS hdd layout the temp partition is an FAT format - so it can be easily mounted on Windows and OSx laptops by just connecting it to such laptops. Use this for easy export data. To import data make sure to work with the data before bootstrap is deleting the directory on startup." > ./README.txt
  mv ./README.txt /mnt/hdd/temp/README.txt 2>/dev/null

  echo "The /mnt/hdd/app-data directory should be used by additional/optional apps and services installed to the RaspiBlitz for their data that should survive an import/export/backup. Data that can be reproduced (indexes, etc.) should be stored in app-storage." > ./README.txt
  mv ./README.txt /mnt/hdd/app-data/README.txt 2>/dev/null

  echo "The /mnt/hdd/app-storage directory should be used by additional/optional apps and services installed to the RaspiBlitz for their non-critical and reproducible data (indexes, public blockchain, etc.) that does not need to survive an an import/export/backup. Data is critical should be in app-data." > ./README.txt
  mv ./README.txt /mnt/hdd/app-storage/README.txt 2>/dev/null

  >&2 echo "# OK - all symbolic links are built"
  exit 0
fi

########################################
# SWAP on data drive
########################################

if [ "$1" = "swap" ]; then
  >&2 echo "# RASPIBLITZ DATA DRIVES - SWAP FILE"
  if [ ${isMounted} -eq 0 ]; then
    echo "error='no data drive mounted'"
    exit 1
  fi
  if [ "$2" = "on" ]; then
    if [ ${isSwapExternal} -eq 1 ]; then
      >&2 echo "# OK - already ON"
      exit 1
    fi
    >&2 echo "# Switch off/uninstall old SWAP"
    dphys-swapfile swapoff 1>/dev/null
    dphys-swapfile uninstall 1>/dev/null
    if [ ${isBTRFS} -eq 1 ]; then
      >&2 echo "# Rewrite external SWAP config for BTRFS setup"
      sed -i "s/^#CONF_SWAPFILE=/CONF_SWAPFILE=/g" /etc/dphys-swapfile  
      sed -i "s/^CONF_SWAPFILE=.*/CONF_SWAPFILE=\/mnt\/temp\/swapfile/g" /etc/dphys-swapfile  
    else
      >&2 echo "# Rewrite external SWAP config for EXT4 setup"
      sed -i "s/^#CONF_SWAPFILE=/CONF_SWAPFILE=/g" /etc/dphys-swapfile  
      sed -i "s/^CONF_SWAPFILE=.*/CONF_SWAPFILE=\/mnt\/hdd\/swapfile/g" /etc/dphys-swapfile  
    fi
    sed -i "s/^CONF_SWAPSIZE=/#CONF_SWAPSIZE=/g" /etc/dphys-swapfile 
    sed -i "s/^#CONF_MAXSWAP=.*/CONF_MAXSWAP=10240/g" /etc/dphys-swapfile
    >&2 echo "# Creating SWAP file .."
    dd if=/dev/zero of=$externalSwapPath count=10240 bs=1MiB 1>/dev/null
    chmod 0600 $externalSwapPath 1>/dev/null
    >&2 echo "# Activating new SWAP"
    mkswap $externalSwapPath
    dphys-swapfile setup 
    dphys-swapfile swapon
    >&2 echo "# OK - Swap is now ON external"
    exit 0
  elif [ "$2" = "off" ]; then
    if [ ${isSwapExternal} -eq 0 ]; then
      >&2 echo "# OK - already OFF"
      exit 1
    fi
    
    >&2 echo "# Switch off/uninstall old SWAP"
    dphys-swapfile swapoff 1>/dev/null
    dphys-swapfile uninstall 1>/dev/null

    >&2 echo "# Rewrite SWAP config"
    sed -i "12s/.*/CONF_SWAPFILE=\/var\/swap/" /etc/dphys-swapfile
    sed -i "16s/.*/#CONF_SWAPSIZE=/" /etc/dphys-swapfile
    dd if=/dev/zero of=/var/swap count=256 bs=1MiB 1>/dev/null
    chmod 0600 /var/swap

    >&2 echo "# Create and switch on new SWAP" 
    mkswap /var/swap 1>/dev/null
    dphys-swapfile setup 1>/dev/null
    dphys-swapfile swapon 1>/dev/null

    >&2 echo "# OK - Swap is now OFF external"
    exit 0
  else
    >&2 echo "# FAIL unknown second parameter - try 'on' or 'off'"
    echo "error='unknown parameter'"
    exit 1
  fi
fi

########################################
# CLEAN data drives
########################################

if [ "$1" = "clean" ]; then

  >&2 echo "# RASPIBLITZ DATA DRIVES - CLEANING"

  # get HDD status
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  if [ ${isMounted} -eq 0 ]; then
    >&2 echo "# FAIL: cannot clean - the drive is not mounted'"
    echo "error='not mounted'"
    exit 1
  fi
  >&2 echo "# Making sure 'secure-delete' is installed ..."
  apt-get install -y secure-delete 1>/dev/null
  >&2 echo
  >&2 echo "# IMPORTANT: No 100% guarantee that sensitive data is completely deleted!"
  # see: https://www.davescomputers.com/securely-deleting-files-solid-state-drive/"
  # see: https://unix.stackexchange.com/questions/62345/securely-delete-files-on-btrfs-filesystem"
  >&2 echo "# --> Dont resell or gift data drive. Destroy physically if needed."
  >&2 echo  

  # DELETE ALL DATA (with option to keep blockchain)
  if [ "$2" = "all" ]; then
    if [ "$3" = "-total" ] || [ "$3" = "-keepblockchain" ]; then
      >&2 echo "# Deleting personal Data .."
      
        # make sure swap is off
        dphys-swapfile swapoff 1>/dev/null
        dphys-swapfile uninstall 1>/dev/null
        sync

        # for all other data shred files selectively
        for entry in $(ls -A1 /mnt/hdd)
        do
          delete=1
          whenDeleteSchredd=1
          # dont delete temp - will be deleted on every boot anyway
          # but keep in case during setup a migration file was uploaded there
          if [ "${entry}" = "temp" ]; then
            delete=0
          fi
          # deactivate delete if a blockchain directory (if -keepblockchain)
          if [ "$3" = "-keepblockchain" ]; then
            if [ "${entry}" = "bitcoin" ]; then
              delete=0
            fi
          fi
          # decide when to shred or just delete - just delete nonsensitive data
          if [ "${entry}" = "torrent" ] || [ "${entry}" = "app-storage" ]; then
            whenDeleteSchredd=0
          fi
          if [ "${entry}" = "bitcoin" ]; then
            whenDeleteSchredd=0
          fi
          # if BTRFS just shred stuff in /mnt/hdd/temp (because thats EXT4)
          if [ ${isBTRFS} -eq 1 ] && [ "${entry}" != "temp" ]; then
            whenDeleteSchredd=0
          fi
          # on SSDs never shred
          # https://www.davescomputers.com/securely-deleting-files-solid-state-drive/
          if [ "${isSSD}" == "1" ]; then
            whenDeleteSchredd=0
          fi
          # delete or keep
          if [ ${delete} -eq 1 ]; then
            if [ -d "/mnt/hdd/$entry" ]; then
              if [ ${whenDeleteSchredd} -eq 1 ]; then
                >&2 echo "# shredding DIR  : ${entry}"
                srm -lr /mnt/hdd/$entry
              else
                >&2 echo "# deleting DIR  : ${entry}"
                rm -r /mnt/hdd/$entry
              fi
            else
              if [ ${whenDeleteSchredd} -eq 1 ]; then
                >&2 echo "# shredding FILE : ${entry}"
                srm -l /mnt/hdd/$entry
              else
                >&2 echo "# deleting FILE : ${entry}"
                rm /mnt/hdd/$entry
              fi
            fi
          else
            >&2 echo "# keeping: ${entry}"
          fi
        done

        # KEEP BLOCKCHAIN means just blocks & chainstate - delete the rest
        if [ "$3" = "-keepblockchain" ]; then
          chains=(bitcoin)
          for chain in "${chains[@]}"
          do
            echo "Cleaning Blockchain: ${chain}"
            # take extra care if wallet.db exists
            srm -v /mnt/hdd/${chain}/wallet.db 2>/dev/null
            # the rest just delete (keep blocks and chainstate and testnet3)
            for entry in $(ls -A1 /mnt/hdd/${chain} 2>/dev/null)
            do
              # sorting file
              delete=1
              if [ "${entry}" = "blocks" ] || [ "${entry}" = "chainstate" ]\
              || [ "${entry}" = "testnet3" ] ; then
                delete=0
              fi
              # delete or keep
              if [ ${delete} -eq 1 ]; then
                if [ -d "/mnt/hdd/${chain}/$entry" ]; then
                  >&2 echo "# Deleting DIR  : /mnt/hdd/${chain}/${entry}"
                  rm -r /mnt/hdd/${chain}/$entry
                else
                  >&2 echo "# deleting FILE : /mnt/hdd/${chain}/${entry}"
                  rm /mnt/hdd/${chain}/$entry
                fi
              else
                >&2 echo "# keeping: ${entry}"
              fi
            done

            # keep blocks and chainstate in testnet3 if exists
            if [ -d /mnt/hdd/bitcoin/testnet3 ];then
            for entry in $(ls -A1 /mnt/hdd/bitcoin/testnet3 2>/dev/null)
              do
                # sorting file
                delete=1
                if [ "${entry}" = "blocks" ] || [ "${entry}" = "chainstate" ]; then
                  delete=0
                fi
                # delete or keep
                if [ ${delete} -eq 1 ]; then
                  if [ -d "/mnt/hdd/bitcoin/testnet3/$entry" ]; then
                    >&2 echo "# Deleting DIR  : /mnt/hdd/bitcoin/testnet3/${entry}"
                    rm -r /mnt/hdd/bitcoin/testnet3/$entry
                  else
                    >&2 echo "# deleting FILE : /mnt/hdd/bitcoin/testnet3/${entry}"
                    rm /mnt/hdd/bitcoin/testnet3/$entry
                  fi
                else
                  >&2 echo "# keeping: ${entry}"
                fi
              done
            fi  
          done
        fi
      >&2 echo "# OK cleaning done."
      exit 1
    else
      >&2 echo "# FAIL unknown third parameter try '-total' or '-keepblockchain'"
      echo "error='unknown parameter'"
      exit 1    
    fi

  # RESET BLOCKCHAIN (e.g to rebuilt blockchain )
  elif [ "$2" = "blockchain" ]; then  
    # here is no secure delete needed - because not sensitive data
    >&2 echo "# Deleting all Blockchain Data (blocks/chainstate) from storage .."
    # set path based on EXT4/BTRFS
    basePath="/mnt/hdd"
    if [ ${isBTRFS} -eq 1 ]; then
      basePath="/mnt/storage"
    fi
    # deleting the blocks and chainstate
    rm -R ${basePath}/bitcoin/blocks 1>/dev/null 2>/dev/null
    rm -R ${basePath}/bitcoin/chainstate 1>/dev/null 2>/dev/null
    >&2 echo "# OK cleaning done."
    exit 1
    
  # RESET TEMP (keep swapfile)
  elif [ "$2" = "temp" ]; then  
    >&2 echo "# Deleting the temp folder/drive (keeping SWAP file) .."  
    tempPath="/mnt/hdd/temp"       
    for entry in $(ls -A1 ${tempPath} 2>/dev/null)
    do
      # sorting file
      delete=1
      if [ "${entry}" = "swapfile" ]; then
        delete=0
      fi
      # delete or keep
      if [ ${delete} -eq 1 ]; then
        if [ -d "${tempPath}/$entry" ]; then
          >&2 echo "# shredding DIR  : ${entry}"
          rm -r ${tempPath}/$entry
        else
          >&2 echo "# shredding FILE : ${entry}"
          rm ${tempPath}/$entry
        fi
      else
        >&2 echo "# keeping: ${entry}"
      fi
    done
    >&2 echo "# OK cleaning done."
    exit 1
  else
    >&2 echo "# FAIL unknown second parameter - try 'all','blockchain' or 'temp'"
    echo "error='unknown parameter'"
    exit 1
  fi
fi  

########################################
# UASP-fix
########################################

if [ "$1" = "uasp-fix" ]; then

  # get HDD status and if the connected adapter is supports UASP
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)

  # check if UASP is already deactivated (on RaspiOS)
  # https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
  cmdlineExists=$(ls ${raspi_bootdir}/cmdline.txt 2>/dev/null | grep -c "cmdline.txt")
  if [ ${cmdlineExists} -eq 1 ] && [ ${#hddAdapterUSB} -gt 0 ] && [ ${hddAdapterUSAP} -eq 0 ]; then
    echo "# Checking for UASP deactivation ..."
    usbQuirkActive=$(cat ${raspi_bootdir}/cmdline.txt | grep -c "usb-storage.quirks=")
    usbQuirkDone=$(cat ${raspi_bootdir}/cmdline.txt | grep -c "usb-storage.quirks=${hddAdapterUSB}:u")
    if [ ${usbQuirkActive} -gt 0 ] && [ ${usbQuirkDone} -eq 0 ]; then
      # remove old usb-storage.quirks
      sed -i "s/usb-storage.quirks=[^ ]* //g" ${raspi_bootdir}/cmdline.txt
    fi 
    if [ ${usbQuirkDone} -eq 0 ]; then
      # add new usb-storage.quirks
      sed -i "s/^/usb-storage.quirks=${hddAdapterUSB}:u /" ${raspi_bootdir}/cmdline.txt
      # go into reboot to activate new setting
      echo "# DONE deactivating UASP for ${hddAdapterUSB} ... reboot needed"
      echo "neededReboot=1"
    else
      echo "# Already UASP deactivated for ${hddAdapterUSB}"
      echo "neededReboot=0"
    fi
  else
    echo "# Skipping UASP deactivation ... cmdlineExists(${cmdlineExists}) hddAdapterUSB(${hddAdapterUSB}) hddAdapterUSAP(${hddAdapterUSAP})"
    echo "neededReboot=0"
  fi
  exit 0
fi

echo "error='unkown command'"
exit 1
