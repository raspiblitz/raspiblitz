#!/usr/bin/env bash

# the cache concept of RaspiBlitz has two options
# 1) RAMDISK for files under /var/cache/raspiblitz
# 2) KEY-VALUE STORE for system state infos (REDIS)

# SECURITY NOTE: The files on the RAMDISK can be set with unix file permissions and so restrict certain users access.
# But all data stored in the KEY-VALUE STORE has to be asumed as system-wide public information.

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Cache"
  echo
  echo "*** RAMDISK for files under /var/cache/raspiblitz"
  echo "blitz.cache.sh ramdisk [on|off]"
  echo "blitz.cache.sh keyvalue [on|off]"
  echo
  echo "*** RAMDISK for files under /var/cache/raspiblitz"
  echo "blitz.cache.sh set [key] [value] [?expire-seconds]"
  echo "blitz.cache.sh get [key1] [?key2] [?key3] ..."
  echo
  exit 1
fi

###################
# RAMDISK
###################

# install
if [ "$1" = "ramdisk" ] && [ "$2" = "on" ]; then

  echo "# Turn ON: RAMDISK"

  if ! grep -Eq '^tmpfs.*/var/cache/raspiblitz' /etc/fstab; then

    if grep -Eq '/var/cache/raspiblitz' /etc/fstab; then
      # entry is in file but most likely just disabled -> re-enable it
      sudo sed -i -E 's|^#(tmpfs.*/var/cache/raspiblitz.*)$|\1|g' /etc/fstab
    else
      # missing -> add
      echo "" | sudo tee -a /etc/fstab >/dev/null
      echo "tmpfs         /var/cache/raspiblitz  tmpfs  nodev,nosuid,size=32M  0  0" | sudo tee -a /etc/fstab >/dev/null
    fi
  fi

  if ! findmnt -l /var/cache/raspiblitz >/dev/null; then
    sudo mkdir -p /var/cache/raspiblitz
    sudo mount /var/cache/raspiblitz
  fi


# uninstall
elif [ "$1" = "ramdisk" ] || [ "$2" = "off" ]; then

  echo "# Turn OFF: RAMDISK"

  if grep -Eq '/var/cache/raspiblitz' /etc/fstab; then
    sudo sed -i -E 's|^(tmpfs.*/var/cache/raspiblitz.*)$|#\1|g' /etc/fstab
  fi

  if findmnt -l /var/cache/raspiblitz >/dev/null; then
    sudo umount /var/cache/raspiblitz
  fi

###################
# KEYVALUE (REDIS)
###################

# install
elif [ "$1" = "keyvalue" ] && [ "$2" = "on" ]; then

  echo "# Turn ON: KEYVALUE-STORE (REDIS)"
  sudo apt install -y redis-server


# uninstall
elif [ "$1" = "keyvalue" ] && [ "$2" = "off" ]; then

  echo "# Turn OFF: KEYVALUE-STORE (REDIS)"
  sudo apt remove -y redis-server

# set
elif [ "$1" = "set" ]; then

  echo "#TODO: set"

# get
elif [ "$1" = "get" ]; then

  position=0
  for keystr in $@
  do
    ((position++))
    if [ $position -eq 1 ]; then
      echo "# blitz.cache.sh $@"
      continue
    fi
    echo "${keystr}=\"\""
  done

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
