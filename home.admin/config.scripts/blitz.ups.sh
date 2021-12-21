#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

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

  if [ "$2" = "apcusb" ]; then
   
    # MODEL: APC with USB connection
    # see video: https://www.youtube.com/watch?v=6UrknowJ12o

    # installs apcupsd.service
    sudo apt-get install -y apcupsd

    # edit config: /etc/apcupsd/apcupsd.conf
    sudo systemctl stop apcupsd
    sudo systemctl disable apcupsd

    # make service autostart
    sudo sed -i '3iAfter=background.service' /lib/systemd/system/apcupsd.service
    sudo sed -i '3iWants=background.service' /lib/systemd/system/apcupsd.service

    sudo sed -i "s/^UPSCABLE.*/UPSCABLE usb/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^UPSTYPE.*/UPSTYPE usb/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^DEVICE.*/DEVICE/g" /etc/apcupsd/apcupsd.conf
    # give the RaspiBlitz a minimum of 15 min to shutdown
    sudo sed -i "s/^MINUTES.*/MINUTES 15/g" /etc/apcupsd/apcupsd.conf
    # some APC UPS were not running stable below 90% Battery - so start shutdown at 95% remaining
    sudo sed -i "s/^BATTERYLEVEL.*/BATTERYLEVEL 95/g" /etc/apcupsd/apcupsd.conf
    sudo sed -i "s/^ISCONFIGURED=.*/ISCONFIGURED=yes/g" /etc/default/apcupsd
    sudo sed -i "s/^SHUTDOWN=.*/SHUTDOWN=\/home\/admin\/config.scripts\/blitz.shutdown.sh/g" /etc/apcupsd/apccontrol
    sudo sed -i "s/^WALL=.*/#WALL=wall/g" /etc/apcupsd/apccontrol
    sudo systemctl enable apcupsd
    sudo systemctl start apcupsd
    
    # set ups config value (in case of update)
    /home/admin/config.scripts/blitz.conf.sh set ups "apcusb"

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
  if [ ${#ups} -eq 0 ] || [ "${ups}" = "off" ]; then
    echo "upsStatus='OFF'"
    exit 0
  fi

  if [ "${ups}" = "apcusb" ]; then
    status=$(apcaccess -p STATUS 2>/dev/null | xargs)
    if [ ${#status} -eq 0 ]; then
      echo "upsStatus='n/a'"
    else
      echo "upsStatus='${status}'"
      # get battery level if possible
      if [ "${status}" = "ONLINE" ] || [ "${status}" = "ONBATT" ]; then
        battery=$(apcaccess -p BCHARGE | xargs | cut -d "." -f1)
        echo "upsBattery=${battery}"
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
  if [ ${#ups} -eq 0 ] || [ "${ups}" = "off" ]; then
    echo "FAIL: UPS is already off."
    exit 1
  fi

  if [ "${ups}" = "apcusb" ]; then
    sudo systemctl stop apcupsd
    sudo systemctl disable apcupsd
    sudo apt-get remove -y apcupsd
    /home/admin/config.scripts/blitz.conf.sh set ups "off"
  else
    echo "FAIL: unknown UPSTYPE: ${ups}"
    exit 1
  fi

fi
