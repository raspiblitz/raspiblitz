#!/bin/bash
# see issue: https://github.com/rootzoll/raspiblitz/issues/681

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "flip/rotate the LCD screen"
 echo "blitz.lcdrotate.sh [on|off]"
 exit 1
fi

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: LCD ROTATE"

  # add default 'lcdrotate' raspiblitz.conf if needed
  if [ ${#lcdrotate} -eq 0 ]; then
    echo "lcdrotate=1" >> /mnt/hdd/raspiblitz.conf
  fi
  
  sudo sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=270/g" /boot/config.txt
  sudo sed -i "s/^lcdrotate=.*/lcdrotate=1/g" /mnt/hdd/raspiblitz.conf
  
  # if touchscreen is on
  if [ "${touchscreen}" = "1" ]; then
    echo "Also rotate touchscreen ..."
    cat << EOF | sudo tee /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null
Section "InputClass"
        Identifier "libinput touchscreen catchall"
        MatchIsTouchscreen "on"
        Option "CalibrationMatrix" "0 1 0 -1 0 1 0 0 1"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
EndSection
EOF
  fi

  echo "OK - a restart is needed: sudo shutdown -r now"

fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: LCD ROTATE"

  # add default 'lcdrotate' raspiblitz.conf if needed
  if [ ${#lcdrotate} -eq 0 ]; then
    echo "lcdrotate=0" >> /mnt/hdd/raspiblitz.conf
  fi

  sudo sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=90/g" /boot/config.txt
  sudo sed -i "s/^lcdrotate=.*/lcdrotate=0/g" /mnt/hdd/raspiblitz.conf
  
  # delete possible touchscreen rotate
  sudo rm /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null


  echo "OK - a restart is needed: sudo shutdown -r now"

fi
