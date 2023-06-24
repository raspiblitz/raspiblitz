#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# ---------------------------------------------------"
 echo "# BACKUP RASPIBLITZ"
 echo "# ---------------------------------------------------"
 echo "# blitz.backup.sh hdd"
 echo "# blitz.backup.sh files"
 exit 1
fi

# 1st PARAMETER all other: action
mode="$1"

################################
# RASPIBLITZ - BACKUP
################################

echo "# *** RASPIBLITZ --> BACKUP"
fileowner="admin"
timestamp=$(date +%Y%m%d%H%M)
filename="/mnt/backup/raspiblitz-backup-${timestamp}.tar.gz"

source <(/home/admin/config.scripts/blitz.backupdevice.sh status)
if [ $isMounted == 0 ]; then
   echo "# BACKUPDEVICE NOT MOUNTED"
   exit 1
fi

echo "Backing up ..."

if [ ${mode} == "hdd" ]; then

  # tar it
  sudo tar --exclude="/mnt/hdd/bitcoin/blocks" -zcvf ${filename} /mnt/hdd 1>&2
  sudo chown ${fileowner}:${fileowner} ${filename} 1>&2

elif [ ${mode} == "files" ]; then
        sudo mkdir /mnt/backup/${timestamp}

        sudo cp -r /mnt/hdd/custom /mnt/backup/${timestamp}
        sudo cp -r /mnt/hdd/app-data/custom /mnt/backup/${timestamp}

        sudo cp /home/admin/*.log /mnt/backup/${timestamp}
        sudo cp /home/admin/*.info /mnt/backup/${timestamp}
        sudo cp /mnt/hdd/raspiblitz.conf /mnt/backup/${timestamp}

        #sudo mv /home/admin/lnd-rescue*.tar.gz /mnt/backup/${timestamp}
else
     echo "# unknown parameter"
     exit 1
fi

echo "Finished"
