#!/bin/bash

# This is for developing on your RaspiBlitz VM

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "FOR DEVELOPMENT USE ONLY!"
  echo "RaspiBlitzVM Sync Scripts"
  echo "blitz.vm.sh sync  -> syncs the code from /mnt/vm_shared_folder"
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

# sync code from shared folder projects
if [ "$1" == "sync" ]; then

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

  #check if contains a raspiblitz repo
  containsRaspiBlitzRepo=$(ls /mnt/vm_shared_folder | grep -wc 'raspiblitz')
  if [ ${containsRaspiBlitzRepo} -eq 0 ]; then
    echo "# /mnt/vm_shared_folder does not contain a raspiblitz repo"
    echo "# make sure to share the directory that contains the raspiblitz repo - not the repo itself"
    echo "# make sure its named 'raspiblitz' and not 'raspiblitz-main' or 'raspiblitz-v1.7'"
    echo "error='no raspiblitz repo'"
    exit 1
  fi

  # raspiblitz main
  echo
  echo  "# ##### RASPIBLITZ REPO"
  echo  "# checking for changes of /mnt/vm_shared_folder/raspiblitz"
  source <(/home/admin/_cache.sh get lastStateRaspiBlitzRepo)
  nowStateRaspiBlitzRepo=$(stat -c %Y "/mnt/vm_shared_folder/raspiblitz")
  echo "# lastStateRaspiBlitzRepo(${lastStateRaspiBlitzRepo})"
  echo "# nowStateRaspiBlitzRepo(${nowStateRaspiBlitzRepo})"
  /home/admin/_cache.sh set lastStateRaspiBlitzRepo "${lastStateRaspiBlitzRepo}"
  if [ "${lastStateRaspiBlitzRepo}" != "${nowStateRaspiBlitzRepo}" ]; then
    echo "# changes detected - syncing"
    echo "TODO: sync /mnt/vm_shared_folder/raspiblitz to /home/admin/raspiblitz"
  else
    echo "# no changes detected - no need for sync"
  fi

  # raspiblitz api
  echo
  echo  "# ##### RASPIBLITZ API REPO"
  if [ ! -d "/mnt/vm_shared_folder/blitz_api" ]; then
    echo "# no repo called 'blitz_api' found in shared folder - skipping sync for RaspiBlitz API"
    exit 0
  fi
  echo  "# checking for changes of /mnt/vm_shared_folder/blitz_api"
  source <(/home/admin/_cache.sh get lastStateRaspiBlitzApiRepo)
  nowStateRaspiBlitzApiRepo=$(stat -c %Y "/mnt/vm_shared_folder/blitz_api")
  echo "# lastStateRaspiBlitzApiRepo(${lastStateRaspiBlitzApiRepo})"
  echo "# nowStateRaspiBlitzApiRepo(${nowStateRaspiBlitzApiRepo})"
  /home/admin/_cache.sh set lastStateRaspiBlitzApiRepo "${lastStateRaspiBlitzApiRepo}"
  if [ "${lastStateRaspiBlitzApiRepo}" != "${nowStateRaspiBlitzApiRepo}" ]; then
    echo "# changes detected - syncing"
    echo "TODO: sync /mnt/vm_shared_folder/blitz_api to /home/admin/blitz_api"
  else
    echo "# no changes detected - no need for sync"
  fi

  exit 0
fi

# in case of unknown command
echo "error='unkown command'"
exit 1