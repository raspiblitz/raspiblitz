#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Time Tools"
  echo
  echo "## SSHD SERVICE #######"
  echo "blitz.ssh.sh choose-timezone    --> user can choose timezone from list and it gets stored to raspiblitz config"
  echo "blitz.ssh.sh set-time-by-config --> resets the time on the RaspiBlitz based on the config"
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

  # Get the list of timezones
  timezones=$(timedatectl list-timezones)

  # Prepare the list for dialog
  timezone_list=()
  for tz in $timezones; do
    timezone_list+=("$tz" "" off)
  done

  # Use dialog to display the list and get the user selection
  choice=$(dialog --clear \
                --backtitle "Timezone Selector" \
                --title "Select a Timezone" \
                --radiolist "Move using [UP] [DOWN],[Space] to Select and [Enter] to Confirm" 20 60 15 \
                "${timezone_list[@]}" 2>&1 >/dev/tty)

  # Clear the screen
  clear

  # Set the chosen timezone
  if [ -n "$choice" ]; then
    echo "# Setting timezone to $choice ..."
    sudo timedatectl set-timezone "$choice"
    echo "# Saving timezone to raspiblitz config ..."
    /home/admin/config.scripts/blitz.config.sh set "timezone" "$choice"
  else
    echo "# No timezone selected"
  fi

  sleep 2
  exit 0
fi

###################
# set-time-by-config
###################
if [ "$1" = "set-time-by-config" ]; then

  exit 0
fi

echo "error='unknown parameter'"
exit 1
