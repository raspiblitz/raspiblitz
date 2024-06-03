#!/bin/bash

# This is for developing on your RaspiBlitz VM

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "FOR DEVELOPMENT USE ONLY!"
  echo "RaspiBlitzVM Sync with repos in /mnt/vm_shared_folder"
  echo "blitz.vm.sh sync      -> syncs all available repos in shared folder"
  echo "blitz.vm.sh sync code -> syncs only the raspiblitz repo"
  echo "blitz.vm.sh sync api  -> syncs only the raspiblitz API repo"
  echo ""
  exit 1
fi

# check runnig as sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='please run as root'"
  exit 1
fi

# check if running in vm
isVM=$(grep -c 'hypervisor' /proc/cpuinfo)
if [ ${isVM} -eq 0 ]; then
  echo "# This script is only for RaspiBlitz running in a VM"
  echo "error='not a VM'"
  exit 1
fi

# check if shared folder exists
if [ ! -d "/mnt/vm_shared_folder" ]; then
  echo "# Creating shared folder /mnt/vm_shared_folder"
  mkdir /mnt/vm_shared_folder
  chmod 777 /mnt/vm_shared_folder
fi

# check if shared folder is mounted
isMounted=$(mount | grep '/mnt/vm_shared_folder')
if [ ${#isMounted} -eq 0 ]; then
  echo "# Mounting shared folder /mnt/vm_shared_folder"
  mount -t 9p -o trans=virtio share /mnt/vm_shared_folder
  if [ $? -eq 0 ]; then
    echo "# OK - shared folder mounted"
  else
    echo "# make sure to activate shared folder in VM settings (VirtFS)"
    echo "error='mount failed'"
    exit 1
  fi
fi

# RASPIBLITZ MAIN REPO
if [ "$2" == "code" ] || [ "$2" == "" ]; then

  echo
  echo  "# ##### RASPIBLITZ REPO"

  #check if contains a raspiblitz MAIN repo
  containsRaspiBlitzRepo=$(ls /mnt/vm_shared_folder | grep -wc 'raspiblitz')
  if [ ${containsRaspiBlitzRepo} -eq 0 ]; then
 
    echo "# /mnt/vm_shared_folder does not contain a raspiblitz repo"
    echo "# make sure to share the directory that contains the raspiblitz repo - not the repo itself"
    echo "# make sure its named 'raspiblitz' and not 'raspiblitz-main' or 'raspiblitz-v1.7'"
 
    if [ "$2" != "" ]; then
      echo "error='no raspiblitz main repo'"
      exit 1
    fi
 
  else

    cd /home/admin
    echo "# COPYING from VM SHARED FOLDER to /home/admin/"
    echo "# - basic admin files"
    rm -f *.sh
    su - admin -c 'cp /mnt/vm_shared_folder/raspiblitz/home.admin/.tmux.conf /home/admin'
    su - admin -c 'cp /mnt/vm_shared_folder/raspiblitz/home.admin/*.* /home/admin 2>/dev/null'
    su - admin -c 'chmod 755 *.sh'
    echo "# - asset directory"
    rm -rf assets
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblitz/home.admin/assets /home/admin/assets'
    echo "# - config.scripts directory"
    rm -rf /home/admin/config.scripts
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblitz/home.admin/config.scripts /home/admin/config.scripts'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.sh'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.py'
    echo "# - setup.scripts directory"
    rm -rf /home/admin/setup.scripts
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblitz/home.admin/setup.scripts /home/admin/setup.scripts'
    su - admin -c 'chmod 755 /home/admin/setup.scripts/*.sh'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.py'
    echo "# ******************************************"

    if [ "$2" != "" ]; then
      exit 0
    fi

  fi
fi  

# RASPIBLITZ API REPO
if [ "$2" == "api" ] || [ "$2" == "" ]; then

  echo
  echo  "# ##### RASPIBLITZ API REPO"

  # check if blitzapi service is enabled
  systemctl is-enabled blitzapi 2>/dev/null
  notInstalled=$?

  #check if contains a raspiblitz API repo
  containsApiRepo=$(ls /mnt/vm_shared_folder | grep -wc 'blitz_api')
  if [ ${containsApiRepo} -eq 0 ]; then
 
    echo "# /mnt/vm_shared_folder does not contain a api repo"
    echo "# make sure to share the directory that contains the api repo - not the repo itself"
    echo "# make sure its named 'blitz_api'"
 
    if [ "$2" != "" ]; then
      echo "error='no raspiblitz api repo'"
      exit 1
    fi

  elif [ ${notInstalled} -gt 0 ]; then
  
    echo "# blitzapi service is not installed or enabled - skipping"
    if [ "$2" != "" ]; then
      echo "error='blitzapi service not enabled'"
      exit 1
    fi
 
  else

  
    echo "# TODO: Not implemented yet - use /script/updateBlitzAPI.sh instead to sync from host to VM"

    #echo "# Stopping blitzapi service"
    #systemctl stop blitzapi
    #echo "# COPYING from VM SHARED FOLDER to /home/blitzapi/"
    #rm -rf /home/blitzapi/blitz_api
    #cp -R /mnt/vm_shared_folder/blitz_api /home/blitzapi
    #chown -R blitzapi:blitzapi /home/blitzapi/blitz_api
    #cd /home/blitzapi/blitz_api || exit 1
    #su - blitzapi -c './venv/bin/pip install -r requirements.txt'
    #echo "# Starting blitzapi service"
    #systemctl start blitzapi

    if [ "$2" != "" ]; then
      exit 0
    fi

  fi

fi

if [ "$1" == "sync" ]; then
  exit 0
fi

# in case of unknown command
echo "error='unkown command'"
exit 1