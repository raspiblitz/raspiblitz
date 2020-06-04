#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Cache RAM disk"
  echo "blitz.cache.sh [on|off]"
  exit 1
fi

###################
# SWITCH ON
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: Cache"

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

###################
# SWITCH OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: Cache"

  if grep -Eq '/var/cache/raspiblitz' /etc/fstab; then
    sudo sed -i -E 's|^(tmpfs.*/var/cache/raspiblitz.*)$|#\1|g' /etc/fstab
  fi

  if findmnt -l /var/cache/raspiblitz >/dev/null; then
    sudo umount /var/cache/raspiblitz
  fi

else

  echo "# FAIL: parameter not known - run with -h for help"
fi
