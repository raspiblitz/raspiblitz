#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Time Tools"
  echo
  echo "## Parameters #######"
  echo "choose-timezone  --> user can choose timezone from list and it gets stored to raspiblitz config"
  echo "set-by-config    --> resets the time on the RaspiBlitz based on the config"
  exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# choose-timezone
###################
if [ "$1" = "choose-timezone" ]; then

  # Prepare the list of timezones for dialog
  echo "# preparing timezone list ..."
  timezones=$(timedatectl list-timezones)
  timezone_list=()
  i=1
  for tz in $timezones; do
    prefix=$(echo $tz | cut -c1)
    timezone_list+=("${prefix}${i}" "$tz")
    i=$((i+1))
  done

  # Use dialog to display the list and get the user selection
  choice=$(dialog --clear \
                --backtitle "Timezone Selector" \
                --title "Select a Timezone" \
                --menu "Choose a timezone:" 20 60 15 \
                "${timezone_list[@]}" 2>&1 >/dev/tty)

  # Clear the screen
  clear

  # Set the chosen timezone
  if [ -n "$choice" ]; then
    index=$(echo "$choice" | sed 's/^[A-Z]//')
    selected_timezone=${timezone_list[((index * 2) - 1)]}
    echo "# Setting timezone to $selected_timezone ..."
    timedatectl set-timezone "$selected_timezone"
    echo "# Saving timezone to raspiblitz config ..."
    /home/admin/config.scripts/blitz.conf.sh set "timezone" "$selected_timezone"
  else
    echo "# No timezone selected"
  fi

  sleep 2
  exit 0
fi

###################
# set-by-config
###################
if [ "$1" = "set-by-config" ]; then
  source /mnt/hdd/raspiblitz.conf
  if [ ${#timezone} -eq 0 ]; then
    echo "# no timezone set in raspiblitz.conf ... keeping default timezone"
    exit 1
  fi
  echo "# Setting timezone to $timezone ..."
  timedatectl set-timezone "$timezone"
  exit 0
fi

echo "error='unknown parameter'"
exit 1
