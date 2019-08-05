#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Configure a UPS (Uninterruptible Power Supply)"
 echo "blitz.ups.sh on apcusb"
 echo "blitz.ups.sh status"
 echo "blitz.ups.sh off"
 exit 1
fi

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: UPS"

  # check if already activated
  if [ ${#ups} -gt 0 ]; then
    echo "FAIL: UPS is already on - switch off with: ./blitz.ups.sh off"
    exit 1
  fi

  if [ "$2" = "apcusb" ]; then
   
    # MODEL: APC with USB connection
    # see video: https://www.youtube.com/watch?v=6UrknowJ12o

    # installs apcupsd.service
    sudo apt-get install -f apcupsd

    # edit config: /etc/apcupsd/apcupsd.conf
    sudo systemctl stop apcupsd
    sudo sed -i "s/^UPSCABLE.*/UPSCABLE usb/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^UPSTYPE.*/UPSTYPE usb/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^DEVICE.*/DEVICE/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^MINUTES.*/MINUTES 10/g" /etc/apcupsd/apcupsd.conf
    sudo systemctl start apcupsd

    # add default 'ups' raspiblitz.conf if needed
    if [ ${#ups} -eq 0 ]; then
      echo "ups=" >> /mnt/hdd/raspiblitz.conf
    fi
    # set ups config value (in case of update)
    sudo sed -i "s/^ups=.*/ups='apcusb'/g" /mnt/hdd/raspiblitz.conf

    echo "OK - UPS is now connected"
    echo "Check status/connection with command: apcaccess"

  else
    echo "FAIL: unknown or missing second parameter 'UPSTYPE'"
    exit 1
  fi

fi

###################
# STATUS
###################

if [ "$1" = "status" ]; then
  
  # check if already activated
  if [ ${#ups} -eq 0 ]; then
    echo "upsStatus='OFF'"
    exit 0
  fi

  if [ "${ups}" = "apcusb" ]; then
    status=$(apcaccess -p STATUS | xargs)
    if [ ${#status} -eq 0 ]; then
      echo "upsStatus='n/a'"
    else
      # get battery level if possible
      if [ "${status}" = "ONLINE" ] || [ "${status}" = "ONBATT" ]; then
        status=$(apcaccess -p BCHARGE | xargs | cut -d "." -f1)
        echo "upsStatus='${status}%'"
      else
        echo "upsStatus='${status}'"
      fi
    fi
    exit 0
  else
    echo "upsStatus='CONFIG'"
    exit 0
  fi

fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: UPS"

  # check if already activated
  if [ ${#ups} -eq 0 ]; then
    echo "FAIL: UPS is already off."
    exit 1
  fi

  if [ "${ups}" = "apcusb" ]; then
    sudo systemctl stop apcupsd
    sudo systemctl disable apcupsd
    sudo apt-get remove -f apcupsd
  else
    echo "FAIL: unknown UPSTYPE: ${ups}"
    exit 1
  fi

fi
