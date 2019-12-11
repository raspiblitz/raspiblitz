#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the data drive(s) with old EXT4 or new BTRFS"
 echo "# blitz.datadrive.sh [status|tempmount|format|raid|link|swap|clean|snapshots]"
 echo "ERROR='missing parameters'"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "ERROR='missing sudo'"
  exit 1
fi

# install BTRFS if needed
btrfsInstalled=$(btrfs --version 2>/dev/null | grep -c "btrfs-progs")
if [ ${btrfsInstalled} -eq 0 ]; then
  echo "# Installing BTRFS ..."
  sudo apt-get install -y btrfs-tools 1>/dev/null
fi
btrfsInstalled=$(btrfs --version 2>/dev/null | grep -c "btrfs-progs")
if [ ${btrfsInstalled} -eq 0 ]; then
  echo "error='missing btrfs package'"
  exit 1
fi

###################
# STATUS
###################

# gathering system info
# is global so that also other parts of this script can use this

# basics
isMounted=$(sudo df | grep -c /mnt/hdd)
isBTRFS=$(sudo btrfs subvolume list /mnt/hdd 2>/dev/null | grep -c "WORKINGDIR")
isRaid=$(btrfs filesystem df /mnt/hdd 2>/dev/null | grep -c "Data, RAID1")

# determine if swap is external on or not
externalSwapPath="/mnt/hdd/swapfile"
if [ ${isBTRFS} -eq 1 ]; then
  externalSwapPath="/mnt/temp/swapfile"
fi
isSwapExternal=$(swapon -s | grep -c "${externalSwapPath}")

# output and exit if just status action
if [ "$1" = "status" ]; then

  echo "# RASPIBLITZ DATA DRIVE Status"  
  echo

  echo "# BASICS"
  echo "isMounted=${isMounted}"
  echo "isBTRFS=${isBTRFS}"
  echo

  # if HDD is not mounted system is in the pre-setup phase
  # deliver all the detailes needed about the data drive
  # and it content for the setup dialogs
  if [ ${isMounted} -eq 0 ]; then
    echo "# SETUP INFO"

    # find the HDD (biggest single device)
    size=0
    lsblk -o NAME | grep "^sd" | while read -r usbdevice ; do
      testsize=$(lsblk -o NAME,SIZE -b | grep "^${usbdevice}" | awk '$1=$1' | cut -d " " -f 2)
      if [ ${testsize} -gt ${size} ]; then
        size=${testsize}
        echo "${usbdevice}" > .hdd.tmp
      fi
    done
    hdd=$(cat .hdd.tmp 2>/dev/null)
    rm -f .hdd.tmp 1>/dev/null 2>/dev/null
    echo "hddCandidate='${hdd}'"

    if [ ${#hdd} -gt 0 ]; then

      # check size in bytes and GBs
      size=$(lsblk -o NAME,SIZE -b | grep "^${hdd}" | awk '$1=$1' | cut -d " " -f 2)
      echo "hddBytes=${size}"
      hddGigaBytes=$(echo "scale=0; ${size}/1024/1024/1024" | bc -l)
      echo "hddGigaBytes=${hddGigaBytes}"
  
      # check if single drive with that size
      hddCount=$(lsblk -o NAME,SIZE -b | grep "^sd" | grep -c ${size})
      echo "hddCount=${hddCount}"

      # check format of devices first partition
      hddFormat=$(lsblk -o FSTYPE,NAME,TYPE | grep part | grep "${hdd}1" | cut -d " " -f 1)
      echo "hddFormat='${hddFormat}'"

      # if 'ext4' or 'btrfs' then temp mount and investigate content
      if [ "${hddFormat}" = "ext4" ] || [ "${hddFormat}" = "btrfs" ]; then

        # BTRFS is working with subvolumnes for snapshots / ext4 has no SubVolumes
        subVolumeDir=""
        if [ "${hddFormat}" = "btrfs" ]; then
          subVolumeDir="/WORKINGDIR"
        fi

        # temp mount data drive
        sudo mkdir -p /mnt/hdd
        sudo mount /dev/${hdd}1 /mnt/hdd

        isTempMounted=$(df | grep /mnt/hdd | grep -c ${hdd})
        if [ ${isTempMounted} -eq 0 ]; then
          echo "hddError='data mount failed'"
        else
          # check for recoverable RaspiBlitz data (if config file exists)
          hddRaspiData=$(sudo ls -l /mnt/hdd${subVolumeDir} | grep -c raspiblitz.conf)
          echo "hddRaspiData=${hddRaspiData}"
          sudo umount /mnt/hdd
        fi

        # temp storage data drive
        sudo mkdir -p /mnt/storage
        if [ "${hddFormat}" = "btrfs" ]; then
          # in btrfs setup the second partition is storage partition
          sudo mount /dev/${hdd}2 /mnt/storage
        else
          # in ext4 setup the first partition is also the storage partition
          sudo mount /dev/${hdd}1 /mnt/storage
        fi
        isTempMounted=$(df | grep /mnt/storage | grep -c ${hdd})
        if [ ${isTempMounted} -eq 0 ]; then
          echo "hddError='storage mount failed'"
        else
          # check for blockchain data on storage
          hddBlocksBitcoin=$(sudo ls /mnt/storage${subVolumeDir}/bitcoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
          echo "hddBlocksBitcoin=${hddBlocksBitcoin}"
          hddBlocksLitecoin=$(sudo ls /mnt/storage${subVolumeDir}/litecoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
          echo "hddBlocksLitecoin=${hddBlocksLitecoin}"
          sudo umount /mnt/storage
        fi
      else
        # if not ext4 or btrfs - there is no usable data
        echo "hddRaspiData=0"
        echo "hddBlocksBitcoin=0"
        echo "hddBlocksLitecoin=0"
      fi
    fi
    echo ""  
  fi

  echo "# RAID"
  echo "isRaid=${isRaid}"
  # extra information about not mounted drives (if raid is off)
  if [ ${isMounted} -eq 1 ] && [ ${isBTRFS} -eq 1 ]; then
    if [ ${isRaid} -eq 0 ]; then
      drivecounter=0
      for disk in $(lsblk -o NAME,TYPE | grep "disk" | awk '$1=$1' | cut -d " " -f 1)
      do
        isMounted=$(lsblk -o MOUNTPOINT,NAME | grep "$disk" | grep -c "^/")
        if [ ${isMounted} -eq 0 ]; then
          mountoption=$(lsblk -o NAME,SIZE,VENDOR | grep "^$disk" | awk '$1=$1')
          echo "raidCandidate[${drivecounter}]='${mountoption}'"
          drivecounter=$(($drivecounter +1))
        fi
      done
      echo "raidCandidates=${drivecounter}"
    else
      # identify RAID devices (if RAID is active)
      raidHddDev=$(lsblk -o NAME,MOUNTPOINT | grep "/mnt/hdd" | awk '$1=$1' | cut -d " " -f 1 | sed 's/[^0-9a-z]*//g')
      raidUsbDev=$(sudo btrfs filesystem show /mnt/hdd | grep -F -v "${raidHddDev}" | grep "/dev/" | cut -d "/" --f 3)
      echo "raidHddDev='${raidHddDev}'"
      echo "raidUsbDev='${raidUsbDev}'"
    fi
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

# check basics for formating
if [ "$1" = "format" ]; then
  
  # check valid format
  if [ "$2" = "btrfs" ]; then
    echo "# DATA DRIVE - FORMATTING to new BTRFS layout (new)"
  elif [ "$2" = "ext4" ]; then
    echo "# DATA DRIVE - FORMATTING to new EXT4 layout (old)"
  else
    echo "# missing valid second parameter: 'btrfs' or 'ext4'"
    echo "error='missing parameter'"
    exit 1
  fi

  # get device name to format
  hdd=$3
  if [ ${#hdd} -eq 0 ]; then
    echo "# missing valid third parameter as the device (like 'sda')"
    echo "# run 'status' to see cadidate devices"
    echo "error='missing parameter'"
    exit 1
  fi

  # check if device is existing and a disk (not a partition)
  isValid=$(lsblk -o NAME,TYPE | grep disk | grep -c "${hdd}")
  if [ ${isValid} -eq 0 ]; then
    echo "# either given device was not found"
    echo "# or is not of type disk - see 'lsblk'"
    echo "error='device not valid'"
    exit 1
  fi

  echo "# Checking on SWAP"
  if [ ${isSwapExternal} -eq 1 ]; then
    echo "# Switching off external SWAP"
    sudo dphys-swapfile swapoff 1>/dev/null
    sudo dphys-swapfile uninstall 1>/dev/null
  fi

  echo "# Unmounting all data drives"
  # remove device from all system mounts (also fstab)
  lsblk -o NAME,UUID | grep "${hdd}" | awk '$1=$1' | cut -d " " -f 2 | grep "-" | while read -r uuid ; do
    echo "# Cleaning /etc/fstab from ${uuid}"
    sudo sed -i "/UUID=${uuid}/d" /etc/fstab
    sync
  done
  sudo mount -a

  # unmount drives
  sudo umount /mnt/hdd 2>/dev/null
  sudo umount /mnt/temp 2>/dev/null
  sudo umount /mnt/storage 2>/dev/null
  unmounted1=$(df | grep -c "/mnt/hdd")
  if [ ${unmounted1} -gt 0 ]; then
    echo "error='failed to unmount /mnt/hdd'"
    exit 1
  fi
  unmounted2=$(df | grep -c "/mnt/temp")
  if [ ${unmounted2} -gt 0 ]; then
    echo "error='failed to unmount /mnt/temp'"
    exit 1
  fi
  unmounted3=$(df | grep -c "/mnt/storage")
  if [ ${unmounted3} -gt 0 ]; then
    echo "error='failed to unmount /mnt/storage'"
    exit 1
  fi

  # wipe all partitions and write fresh GPT
  echo "# Wiping all partitions"
  for v_partition in $(parted -s /dev/${hdd} print|awk '/^ / {print $1}')
  do
   sudo parted -s /dev/${hdd} rm ${v_partition}
   sleep 2
  done
  partitions=$(lsblk | grep -c "─${hdd}")
  if [ ${partitions} -gt 0 ]; then
    echo "error='partition cleaning failed'"
    exit 1
  fi
  sudo parted -s /dev/${hdd} mklabel gpt 1>/dev/null
  sleep 2
  sync

fi

# formatting old: EXT4
if [ "$1" = "format" ] && [ "$2" = "ext4" ]; then

  # write new EXT4 partition
  echo "# Creating the one big partion"
  sudo parted /dev/${hdd} mkpart primary ext4 0% 100% 1>/dev/null 2>/dev/null
  sleep 6
  sync
  # loop until the partion gets available
  done=0
  loopcount=0
  while [ ${done} -eq 0 ]
  do
    echo "# waiting until the partion gets available"
    sleep 2
    sync
    done=$(lsblk -o NAME | grep -c ${hdd}1)
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 10 ]; then
      echo "error='partition failed'"
      exit 1
    fi
  done

  # make sure /mnt/hdd is unmounted before formatting
  sudo umount -f /mnt/hdd 2>/dev/null
  unmounted=$(df | grep -c "/mnt/hdd")
  if [ ${unmounted} -gt 0 ]; then
    echo "error='failed to unmount /mnt/hdd'"
    exit 1
  fi

  echo "# Formatting"
  sudo mkfs.ext4 -F -L BLOCKCHAIN /dev/${hdd}1 1>/dev/null
  done=0
  loopcount=0
  while [ ${done} -eq 0 ]
  do
    echo "# waiting until formatted drives gets available"
    sleep 2
    sync
    done=$(lsblk -o NAME,LABEL | grep -c BLOCKCHAIN)
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 10 ]; then
      echo "error='formatting ext4 failed'"
      exit 1
    fi
  done

  # loop until the uuids are available
  uuid1=""
  loopcount=0
  while [ ${#uuid1} -eq 0 ]
  do
    echo "# waiting until uuid gets available"
    sleep 2
    sync
    uuid1=$(lsblk -o NAME,UUID | grep "${hdd}" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 10 ]; then
      echo "error='no uuid after format'"
      exit 1
    fi
  done

  # write new /etc/fstab & mount
  echo "# updating /etc/fstab & mount"
  sudo mkdir -p /mnt/hdd 1>2&
  sudo sed "3 a UUID=${uuid1} /mnt/hdd ext4 noexec,defaults 0 2" -i /etc/fstab 1>/dev/null
  sync
  sudo mount -a 1>/dev/null

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
      echo "# WARNING was not able freshly mount new devives - might need reboot or check /etc/fstab"
      echo "needsReboot=1"
      exit 0
    fi
  done

  echo "# OK EXT 4  format done"
  exit 0

fi

# formatting new: BTRFS layout - this consists of 3 volmunes:
# 1) BLITZDATA - a BTRFS partion for all RaspiBlitz data - 30GB
#    here put all files of LND, app, etc that need backup
# 2) BLITZSTORE - a BTFRS partion for mostly Blockchain data
#    all data here can get lost and rebuild if needed (Blockchain, Indexes, etc)
# 3) BLITZTEMP - a FAT partition just for SWAP & Exchange - 34GB
#    used for SWAP file and easy to read from Win32/MacOS for exchange
#    this directory should get cleaned on every start (except from swap)
if [ "$1" = "format" ] && [ "$2" = "btrfs" ]; then

  # prepare temo mount point
  sudo mkdir -p /tmp/btrfs 1>/dev/null

  echo "# Creating BLITZDATA"
  sudo parted -s -a optimal -- /dev/${hdd} mkpart primary btrfs 0% 30GiB 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME | grep -c ${hdd}1)
  if [ ${win} -eq 0 ]; then 
    echo "error='partition failed'"
    exit 1
  fi
  sudo mkfs.btrfs -f -L BLITZDATA /dev/${hdd}1 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME,LABEL | grep -c BLITZDATA)
  if [ ${win} -eq 0 ]; then 
    echo "error='formatting failed'"
    exit 1
  fi
  echo "# OK BLITZDATA exists now"
  uuidDATA=$(lsblk -o UUID,NAME,LABEL | grep "${hdd}" | grep "BLITZDATA" | cut -d " " -f 1 | grep "-")

  echo "# UUID -> ${uuidDATA}"
  
  echo "# Creating SubVolume for Snapshots"
  sudo mount /dev/${hdd}1 /tmp/btrfs 1>/dev/null
  if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
    echo "error='mount ${hdd}1 failed'"
    exit 1
  fi
  cd /tmp/btrfs
  sudo btrfs subvolume create WORKINGDIR
  subVolDATA=$(sudo btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
  cd && sudo umount /tmp/btrfs
  echo "# SubvolumeID -> ${subVolDATA}"

  echo "# Creating BLITZSTORAGE"
  sudo parted -s -a optimal -- /dev/${hdd} mkpart primary btrfs 30GiB -34GiB 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME | grep -c ${hdd}2)
  if [ ${win} -eq 0 ]; then 
    echo "error='partition failed'"
    exit 1
  fi
  sudo mkfs.btrfs -f -L BLITZSTORAGE /dev/${hdd}2 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME,LABEL | grep -c BLITZSTORAGE)
  if [ ${win} -eq 0 ]; then 
    echo "error='formatting failed'"
    exit 1
  fi
  echo "# OK BLITZSTORAGE exists now"
  uuidSTORAGE=$(lsblk -o UUID,NAME,LABEL | grep "${hdd}" | grep "BLITZSTORAGE" | cut -d " " -f 1 | grep "-")
  echo "# UUID -> ${uuidSTORAGE}"
  
  echo "# Creating SubVolume for Snapshots"
  sudo mount /dev/${hdd}2 /tmp/btrfs 1>/dev/null
  if [ $(df | grep -c "/tmp/btrfs") -eq 0 ]; then
    echo "error='mount ${hdd}2 failed'"
    exit 1
  fi
  cd /tmp/btrfs
  sudo btrfs subvolume create WORKINGDIR
  subVolSTORAGE=$(sudo btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
  cd && sudo umount /tmp/btrfs
  echo "# SubvolumeID -> ${subVolSTORAGE}"

  echo "# Creating the FAT32 partion"
  sudo parted -s -a optimal -- /dev/${hdd} mkpart primary fat32 -34GiB 100% 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME | grep -c ${hdd}3)
  if [ ${win} -eq 0 ]; then 
    echo "error='partition failed'"
    exit 1
  fi
 
  echo "# Creating Volume BLITZTEMP (format)"
  sudo mkfs -t vfat -n BLITZTEMP /dev/${hdd}3 1>/dev/null
  sync && sleep 3
  win=$(lsblk -o NAME,LABEL | grep -c BLITZTEMP)
  if [ ${win} -eq 0 ]; then 
    echo "error='formatting failed'"
    exit 1
  fi
  echo "# OK BLITZTEMP exists now"
  uuidTEMP=$(lsblk -o LABEL,UUID | grep "BLITZTEMP" | awk '$1=$1' | cut -d " " -f 2 | grep "-")
  echo "# UUID TEMP -> ${uuidTEMP}"

  # write new /etc/fstab & mount
  echo "# Updating /etc/fstab & mount"
  sudo mkdir -p /mnt/hdd 1>/dev/null
  fstabAdd1="UUID=${uuidDATA} /mnt/hdd btrfs noexec,defaults,subvolid=${subVolDATA} 0 2"
  sudo sed "3 a ${fstabAdd1}" -i /etc/fstab 1>/dev/null
  sudo mkdir -p /mnt/storage 1>/dev/null
  fstabAdd2="UUID=${uuidSTORAGE} /mnt/storage btrfs noexec,defaults,subvolid=${subVolSTORAGE} 0 2"
  sudo sed "4 a ${fstabAdd2}" -i /etc/fstab 1>/dev/null  
  sudo mkdir -p /mnt/temp 1>/dev/null
  fstabAdd3="UUID=${uuidTEMP} /mnt/temp vfat noexec,defaults 0 2"
  sudo sed "5 a ${fstabAdd3}" -i /etc/fstab 1>/dev/null
  sync && sudo mount -a 1>/dev/null

  # loop mounts are available
  mountactive1=0
  mountactive2=0
  mountactive3=0   
  loopcount=0
  while [ ${mountactive1} -eq 0 ] || [ ${mountactive2} -eq 0 ] || [ ${mountactive3} -eq 0 ]
  do
    echo "# waiting until mountings are active"
    sleep 2
    sync
    mountactive1=$(df | grep -c /mnt/hdd)
    mountactive2=$(df | grep -c /mnt/temp)
    mountactive3=$(df | grep -c /mnt/storage)  
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 10 ]; then
      echo "# WARNING was not able freshly mount new devives - might need reboot or check /etc/fstab"
      echo "needsReboot=1"
      exit 1
    fi
  done

  echo "# OK BTRFS format done"
  exit 0
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
       echo "# OK - already ON"
       exit
     fi
     echo "# RAID - Adding raid drive to RaspiBlitz data drive"
  elif [ "$2" = "off" ]; then
     if [ ${isRaid} -eq 0 ]; then
       echo "# OK - already OFF"
       exit
     fi
     echo "# RAID - Removing raid drive to RaspiBlitz data drive"  
  else
     echo "# possible 2nd parameter is 'on' or 'off'"  
     echo "error='unkown parameter'"
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
    echo "# FAIL third parameter is missing with the name of the usb device to add"
    echo "error='missing parameter'"
    exit 1
  fi

  # check that dev exists and is unique
  usbdevexists=$(lsblk -o NAME,UUID | grep -c "^${usbdev}")
  if [ ${usbdevexists} -eq 0 ]; then
    echo "# FAIL not found: ${usbdev}"
    echo "error='dev not found'"
    exit 1
  fi
  if [ ${usbdevexists} -gt 1 ]; then
    echo "# FAIL multiple matches: ${usbdev}"
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
    echo "# ERROR: !! NOT IMPLEMENTED YET -> devices seem contain old data"
    echo "# if you dont care about that data: format on other computer with FAT"
    echo "error='old data on dev'"
    exit 1
  fi

  # remove all partions from device
  for v_partition in $(parted -s /dev/${usbdev} print|awk '/^ / {print $1}')
  do
   sudo parted -s /dev/${usbdev} rm ${v_partition}
  done

  # check if usb device is at least 30GB groß
  usbdevsize=$(lsblk -o NAME,SIZE -b | grep "^${usbdev}" | awk '$1=$1' | cut -d " " -f 2)
  if [ ${usbdevsize} -lt 30000000000 ]; then
    echo "# FAIL ${usbdev} is smaller then the minumum 30GB"
    echo "error='dev too small'"
    exit 1
  fi

  # add usb device as raid for data
  echo "# adding ${usbdev} as BTRFS raid1 for /mnt/hdd"
  sudo btrfs device add -f /dev/${usbdev} /mnt/hdd 1>/dev/null
  sudo btrfs filesystem balance start -dconvert=raid1 -mconvert=raid1 /mnt/hdd 1>/dev/null
  
  echo "# OK - ${usbdev} is now part of a RAID1 for your RaspiBlitz data"
  exit 0

fi

# RAID --> OFF
if [ "$1" = "raid" ] && [ "$2" = "off" ]; then
 
  # checking if BTRFS mode
  isBTRFS=$(lsblk -o FSTYPE,MOUNTPOINT | grep /mnt/hdd | awk '$1=$1' | cut -d " " -f 1 | grep -c btrfs)
  if [ ${isBTRFS} -eq 0 ]; then
    echo "error='raid only BTRFS'"
    exit 1
  fi

  echo "# removing USB DEV from RAID"
  sudo btrfs balance start -mconvert=dup -dconvert=single /mnt/hdd 1>/dev/null
  sudo btrfs device remove /dev/${raidUsbDev} /mnt/hdd 1>/dev/null
  
  echo "# OK - RaspiBlitz data is not running in RAID1 anymore - you can remove ${raidUsbDev}"
  exit 0

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
    echo "# second parameter needs to be 'data' or 'storage'"
    echo "error='unknown parameter'"
    exit 1
  fi
  
  echo "# RASPIBLITZ SNAPSHOTS"
  partition=$(df | grep "${subvolume}" | cut -d " " -f 1)
  echo "subvolume='${subvolume}'"
  echo "partition='${partition}'"

  if [ "$3" = "create" ]; then

    echo "# Preparing Snapshot ..."

    # make sure backup folder exists
    sudo mkdir -p ${subvolume}/snapshots

    # delete old backup if existing
    oldBackupExists=$(sudo ls ${subvolume}/snapshots | grep -c backup)
    if [ ${oldBackupExists} -gt 0 ]; then
      echo "# Deleting old snapshot"
      sudo btrfs subvolume delete ${subvolume}/snapshots/backup 1>/dev/null
    fi

    echo "# Creating Snapshot ..."
    sudo btrfs subvolume snapshot ${subvolume} ${subvolume}/snapshots/backup 1>/dev/null
    if [ $(sudo btrfs subvolume list ${subvolume} | grep -c snapshots/backup) -eq 0 ]; then
      echo "error='not created'"
      exit 1
    else
      echo "# OK - Snapshot created"
      exit 0
    fi

  elif [ "$3" = "rollback" ]; then

    # check if an old snapshot exists
    oldBackupExists=$(sudo ls ${subvolume}/snapshots | grep -c backup)
    if [ ${oldBackupExists} -eq 0 ]; then
      echo "error='no old snapshot found'"
      exit 1
    fi

    echo "# Resetting state to old Snapshot ..."
    sudo umount ${subvolume}
    sudo mkdir -p /tmp/btrfs 1>/dev/null
    sudo mount ${partition} /tmp/btrfs
    sudo mv /tmp/btrfs/WORKINGDIR/snapshots/backup /tmp/btrfs/backup
    sudo btrfs subvolume delete /tmp/btrfs/WORKINGDIR
    sudo mv /tmp/btrfs/backup /tmp/btrfs/WORKINGDIR
    subVolID=$(sudo btrfs subvolume show /tmp/btrfs/WORKINGDIR | grep "Subvolume ID:" | awk '$1=$1' | cut -d " " -f 3)
    sudo sed -i "/${subvolumeESC}/d" /etc/fstab
    fstabAdd="UUID=${uuid} ${subvolume} btrfs noexec,defaults,subvolid=${subVolID} 0 2"
    sudo sed "4 a ${fstabAdd}" -i /etc/fstab 1>/dev/null  
    sudo umount /tmp/btrfs
    sudo mount -a
    sync
    if [ $(df | grep -c "${subvolume}") -eq 0 ]; then
      echo "# check drive setting ... rollback seemed to "
      echo "error='failed rollback'"
      exit 1
    fi
    echo "OK - Rollback done"
    exit 0

  else
    echo "# third parameter needs to be 'create' or 'rollback'"
    echo "error='unknown parameter'"
    exit 1 
  fi


fi

###################
# TEMP MOUNT
###################

if [ "$1" = "tempmount" ]; then
  
  if [ ${isMounted} -eq 1 ]; then
    echo "error='already mounted'"
    exit 1
  fi

  if [ ${#hddCandidate} -eq 0 ]; then
    echo "error='no hddCandidate'"
    exit 1
  fi

  if [ "${hddFormat}" = "ext4" ]; then

    # do EXT4 temp mount
    sudo mkdir -p /mnt/hdd 1>/dev/null
    sudo mount /dev/${hddCandidate}1 /mnt/hdd

    # check result
    isMounted=$(df | grep -c "/mnt/hdd")
    if [ ${isMounted} -eq 0 ]; then
      echo "error='temp mount failed'"
    else
      echo "isMounted=1"
      echo "isBTRFS=0"
    fi
    
  elif [ "${hddFormat}" = "btrfs" ]; then

    # prepare mount dirctores
    sudo mkdir -p /mnt/hdd 1>/dev/null
    sudo mkdir -p /mnt/storage 1>/dev/null
    sudo mkdir -p /mnt/temp 1>/dev/null

    # pre temp mount
    sudo mount /dev/${hddCandidate}1 /mnt/hdd
    sudo mount /dev/${hddCandidate}2 /mnt/storage

    # get subvolume UUIDS
    hddUUID=$(sudo btrfs subvolume list -u /mnt/hdd/ | grep "path WORKINGDIR" | awk '$1=$1' | cut -d " " -f 9)
    storageUUID=$(sudo btrfs subvolume list -u /mnt/storage/ | grep "path WORKINGDIR" | awk '$1=$1' | cut -d " " -f 9)
    echo "hddUUID='${hddUUID}'"
    echo "storageUUID='${storageUUID}'"

     # pre temp unmount
    sudo umount /mnt/hdd
    sudo umount /mnt/storage

    # temp mount 
    sudo mount -t btrfs -o subvol=machines,defaults,nodatacow /dev/disk/by-uuid/${hddUUID} /mnt/hdd
    sudo mount -t btrfs -o subvol=machines,defaults,nodatacow /dev/disk/by-uuid/${storageUUID} /mnt/storage
    sudo mount /dev/${hddCandidate}3 /mnt/temp

    # check result
    isMountedA=$(df | grep -c "/mnt/hdd")
    isMountedB=$(df | grep -c "/mnt/storage")
    isMountedC=$(df | grep -c "/mnt/temp")
    if [ ${isMountedA} -eq 0 ] && [ ${isMountedB} -eq 0 ] && [ ${isMountedC} -eq 0 ]; then
      echo "error='temp mount failed'"
    else
      echo "isMounted=1"
      echo "isBTRFS=1"
    fi

  else
    echo "error='no supported hdd format'"
    exit 1
  fi

  # make sure all linkings are correct
  $1="link"

fi

########################################
# LINKING all directories with ln
########################################

if [ "$1" = "link" ]; then

  if [ ${isMounted} -eq 0 ]; then
    echo "error='no data drive mounted'"
    exit 1
  fi

  if [ ${isBTRFS} -eq 1 ]; then
    echo "# Creating BTRFS setup links"
    
    echo "# - linking blockchains into /mnt/hdd"
    sudo mkdir -p /mnt/storage/bitcoin
    sudo chown -R bitcoin:bitcoin /mnt/storage/bitcoin
    sudo ln -s /mnt/storage/bitcoin /mnt/hdd/bitcoin
    sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin
    sudo mkdir -p /mnt/storage/litecoin
    sudo chown -R bitcoin:bitcoin /mnt/storage/litecoin
    sudo ln -s /mnt/storage/litecoin /mnt/hdd/litecoin
    sudo chown -R bitcoin:bitcoin /mnt/hdd/litecoin

    echo "# - linking blockchain for user bitcoin"
    sudo rm /home/bitcoin/.bitcoin 2>/dev/null
    sudo ln -s /mnt/storage/bitcoin /home/bitcoin/.bitcoin
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.bitcoin
    sudo rm /home/bitcoin/.litecoin 2>/dev/null
    sudo ln -s /mnt/storage/litecoin /home/bitcoin/.litecoin
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.litecoin

    echo "# - linking storage into /mnt/hdd"
    sudo mkdir -p /mnt/storage/app-storage
    sudo chown -R bitcoin:bitcoin /mnt/storage/app-storage
    sudo ln -s /mnt/storage/app-storage /mnt/hdd/app-storage
    sudo chown -R bitcoin:bitcoin /mnt/hdd/app-storage 

    echo "# - linking temp into /mnt/hdd"
    sudo ln -s /mnt/temp /mnt/hdd/temp
    sudo chown -R bitcoin:bitcoin /mnt/hdd/temp 

    echo "# - creating snapshots folder"
    sudo mkdir /mnt/hdd/snapshots
    sudo mkdir /mnt/storage/snapshots

  else
    echo "# Creating EXT4 setup links"

    echo "# opening blockchain into /mnt/hdd"
    sudo mkdir -p /mnt/hdd/bitcoin
    sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin
    sudo mkdir -p /mnt/hdd/litecoin
    sudo chown -R bitcoin:bitcoin /mnt/hdd/litecoin

    echo "# linking blockchain for user bitcoin"
    sudo rm /home/bitcoin/.bitcoin 2>/dev/null
    sudo ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.bitcoin
    sudo rm /home/bitcoin/.litecoin 2>/dev/null
    sudo ln -s /mnt/hdd/litecoin /home/bitcoin/.litecoin
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.litecoin

    echo "# creating default storage folders"
    sudo mkdir -p /mnt/hdd/app-storage
    sudo chown -R bitcoin:bitcoin /mnt/hdd/app-storage   
    sudo mkdir -p /mnt/hdd/temp

  fi

  echo "# OK - all symbolic links build"
  exit 0

fi

########################################
# SWAP on data drive
########################################

if [ "$1" = "swap" ]; then

  echo "# RASPIBLITZ DATA DRIVES - SWAP FILE"

  if [ ${isMounted} -eq 0 ]; then
    echo "error='no data drive mounted'"
    exit 1
  fi

  if [ "$2" = "on" ]; then

    if [ ${isSwapExternal} -eq 1 ]; then
      echo "# OK - already ON"
      exit 1
    fi

    echo "# Switch off/uninstall old SWAP"
    sudo dphys-swapfile swapoff 1>/dev/null
    sudo dphys-swapfile uninstall 1>/dev/null

    if [ ${isBTRFS} -eq 1 ]; then

      echo "# Rewrite external SWAP config for BTRFS setup"
      sudo sed -i "12s/.*/CONF_SWAPFILE=\/mnt\/temp\/swapfile/" /etc/dphys-swapfile
      sudo sed -i "16s/.*/#CONF_SWAPSIZE=/" /etc/dphys-swapfile  
    
    else

      echo "# Rewrite external SWAP config for EXT4 setup"
      sudo sed -i "12s/.*/CONF_SWAPFILE=\/mnt\/hdd\/swapfile/" /etc/dphys-swapfile
      sudo sed -i "16s/.*/#CONF_SWAPSIZE=/" /etc/dphys-swapfile

    fi

    echo "# Creating SWAP file .."
    sudo dd if=/dev/zero of=$externalSwapPath count=2048 bs=1MiB 1>/dev/null
    sudo chmod 0600 $externalSwapPath 1>/dev/null

    echo "# Activating new SWAP"
    sudo mkswap $externalSwapPath
    sudo dphys-swapfile setup 
    sudo dphys-swapfile swapon

    echo "# OK - Swap is now ON external"
    exit 0

  elif [ "$2" = "off" ]; then
  
    if [ ${isSwapExternal} -eq 0 ]; then
      echo "# OK - already OFF"
      exit 1
    fi

    echo "# Switch off/uninstall old SWAP"
    sudo dphys-swapfile swapoff 1>/dev/null
    sudo dphys-swapfile uninstall 1>/dev/null

    echo "# Rewrite SWAP config"
    sudo sed -i "12s/.*/CONF_SWAPFILE=\/var\/swap/" /etc/dphys-swapfile
    sudo sed -i "16s/.*/#CONF_SWAPSIZE=/" /etc/dphys-swapfile
    sudo dd if=/dev/zero of=/var/swap count=256 bs=1MiB 1>/dev/null
    sudo chmod 0600 /var/swap

    echo "# Create and switch on new SWAP" 
    sudo mkswap /var/swap 1>/dev/null
    sudo dphys-swapfile setup 1>/dev/null
    sudo dphys-swapfile swapon 1>/dev/null

    echo "# OK - Swap is now OFF external"
    exit 0

  else
    echo "# FAIL unkown second parameter - try 'on' or 'off'"
    echo "error='unkown parameter'"
    exit 1
  fi

fi

########################################
# CLEAN data drives
########################################

if [ "$1" = "clean" ]; then

  echo "# RASPIBLITZ DATA DRIVES - CLEANING"

  if [ ${isMounted} -eq 0 ]; then
    echo "# FAIL: cannot clean - the drive is not mounted'"
    echo "error='not mounted'"
    exit 1
  fi

  echo "# Making sure 'secure-delete' is installed ..."
  sudo apt-get install -y secure-delete 1>/dev/null

  # DELETE ALL DATA (with option to keep blockchain)
  if [ "$2" = "all" ]; then
    
    if [ "$3" = "-total" ] || [ "$3" = "-keepblockchain" ]; then

      echo "# Deleting personal Data .."

        # make sure swap is off
        sudo dphys-swapfile swapoff 1>/dev/null
        sudo dphys-swapfile uninstall 1>/dev/null
        sync

        # if delete total - rm blockchain blocks quick for performance
        if [ "$3" = "-total" ]; then
          echo "# Quick Deleting blockchain block data (non-sensitive)"
          sudo rm -R /mnt/hdd/bitcoin/blocks 1>/dev/null 2>/dev/null
          sudo rm -R /mnt/hdd/bitcoin/chainstate 1>/dev/null 2>/dev/null
          sudo rm -R /mnt/hdd/litecoin/blocks 1>/dev/null 2>/dev/null
          sudo rm -R /mnt/hdd/litecoin/chainstate 1>/dev/null 2>/dev/null
        fi

        # for all other data shred files selectivly
        for entry in $(ls -A1 /mnt/hdd)
        do

          # sorting file
          delete=1
          if [ "$3" = "-keepblockchain" ]; then
            # deactivate delete if a blockchain directory
            if [ "${entry}" = "bitcoin" ] || [ "${entry}" = "litecoin" ]; then
              delete=0
            fi
          fi 

          # delete or keep
          if [ ${delete} -eq 1 ]; then

            if [ -d "/mnt/hdd/$entry" ]; then
              echo "# shredding DIR  : ${entry}"
              sudo srm -r /mnt/hdd/$entry
            else
              echo "# shredding FILE : ${entry}"
              sudo srm /mnt/hdd/$entry
            fi

          else
            echo "# keeping: ${entry}"
          fi

        done

        # KEEP BLOCKCHAIN means just blocks & chainstate - delete the rest
        if [ "$3" = "-keepblockchain" ]; then
          chains=(bitcoin litecoin)
          for chain in "${chains[@]}"
          do
            echo "Cleaning Blockchain: ${chain}"
            for entry in $(ls -A1 /mnt/hdd/${chain} 2>/dev/null)
            do
              # sorting file
              delete=1
              if [ "${entry}" = "blocks" ] || [ "${entry}" = "chainstate" ]; then
                delete=0
              fi
              # delete or keep
              if [ ${delete} -eq 1 ]; then
                if [ -d "/mnt/hdd/${chain}/$entry" ]; then
                  echo "# shredding DIR  : /mnt/hdd/${chain}/${entry}"
                  sudo srm -r /mnt/hdd/${chain}/$entry
                else
                  echo "# shredding FILE : /mnt/hdd/${chain}/${entry}"
                  sudo srm /mnt/hdd/${chain}/$entry
                fi
              else
                echo "# keeping: ${entry}"
              fi
            done
          done
        fi

        # In a BTRFS setup more is to be done to clean sensitive data
        # TODO: secure wipe BLITZDATA & RAID1 if needed (maybe)
        if [  ${isBTRFS} -eq 1 ]; then
          echo "# WARNING! BTRFS may still need a secure delete - crash with hammer if needed:"
          echo "# 1) Your HDD/SSD"
          if [ ${isRaid} -eq 1 ]; then
            echo "# 2) Your RAID USB device"
          fi
          echo "# see: https://unix.stackexchange.com/questions/62345/securely-delete-files-on-btrfs-filesystem"
        fi

      echo "# OK cleaning done."
      exit 1

    else
      echo "# FAIL unkown third parameter try '-total' or '-keepblockchain'"
      echo "error='unkown parameter'"
      exit 1    
    fi

  # RESET BLOCKCHAIN (e.g to rebuilt blockchain )
  elif [ "$2" = "blockchain" ]; then  

    # here is no secure delete needed - because not sensitive data
    echo "# Deleting all Blockchain Data (blocks/chainstate) from storage .."

    # set path based on EXT4/BTRFS
    basePath="/mnt/hdd"
    if [ ${isBTRFS} -eq 1 ]; then
      basePath="/mnt/storage"
    fi

    # deleting the blocks and chainstate
    sudo rm -R ${basePath}/bitcoin/blocks 1>/dev/null 2>/dev/null
    sudo rm -R ${basePath}/bitcoin/chainstate 1>/dev/null 2>/dev/null
    sudo rm -R ${basePath}/litecoin/blocks 1>/dev/null 2>/dev/null
    sudo rm -R ${basePath}/litecoin/chainstate 1>/dev/null 2>/dev/null

    echo "# OK cleaning done."
    exit 1
  
  # RESET TEMP (keep swapfile)
  elif [ "$2" = "temp" ]; then  

    echo "# Deleting the temp folder/drive (keeping SWAP file) .."  

    # set path based on EXT4/BTRFS
    tempPath="/mnt/hdd/temp"
    if [ ${isBTRFS} -eq 1 ]; then
      tempPath="/mnt/temp"
    fi

    # better do secure delete, because temp is used for backups
    # secure-delete works because - also in BTRFS setup, temp is EXT4
        
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
          echo "# shredding DIR  : ${entry}"
          sudo srm -r ${tempPath}/$entry
        else
          echo "# shredding FILE : ${entry}"
          sudo srm ${tempPath}/$entry
        fi

      else
        echo "# keeping: ${entry}"
      fi
    done

    echo "# OK cleaning done."
    exit 1
  
  else
    echo "# FAIL unkown second parameter - try 'all','blockchain' or 'temp'"
    echo "error='unkown parameter'"
    exit 1
  fi

fi  

echo "error='unkown command'"
exit 1