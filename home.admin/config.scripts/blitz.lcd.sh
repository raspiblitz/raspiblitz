#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "flip/rotate the LCD screen"
  echo "blitz.lcd.sh rotate [on|off]"
  echo "blitz.lcd.sh image [path]"
  echo "blitz.lcd.sh qr [datastring]"
  echo "blitz.lcd.sh qr-console [datastring]"
  echo "blitz.lcd.sh hide"
  echo "blitz.lcd.sh hdmi [on|off]"
  exit 1
fi

# load config
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# Make sure needed packages are installed
if [ $(sudo dpkg-query -l | grep "ii  fbi" | wc -l) = 0 ]; then
   sudo apt-get install fbi -y > /dev/null
fi
if [ $(sudo dpkg-query -l | grep "ii  qrencode" | wc -l) = 0 ]; then
   sudo apt-get install qrencode -y > /dev/null
fi

# 1. Parameter: lcd command
command=$1

###################
# ROTATE
# see issue: https://github.com/rootzoll/raspiblitz/issues/681
###################

if [ "${command}" == "rotate" ]; then

  # TURN ROTATE ON (the new default)
  if [ "$2" = "1" ] || [ "$2" = "on" ]; then

    echo "# Turn ON: LCD ROTATE"

    # add default 'lcdrotate' raspiblitz.conf if needed
    if [ ${#lcdrotate} -eq 0 ]; then
      echo "lcdrotate=0" >> /mnt/hdd/raspiblitz.conf
    fi
  
    sudo sed -i "s/^dtoverlay=.*/dtoverlay=tft35a:rotate=90/g" /boot/config.txt
    sudo sed -i "s/^lcdrotate=.*/lcdrotate=1/g" /mnt/hdd/raspiblitz.conf

    # delete possible touchscreen rotate
    sudo rm /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null

    echo "# OK - a restart is needed: sudo shutdown -r now"

  # TURN ROTATE OFF
  elif [ "$2" = "0" ] || [ "$2" = "off" ]; then

    echo "#Turn OFF: LCD ROTATE"

    sudo sed -i "s/^dtoverlay=.*/dtoverlay=tft35a:rotate=270/g" /boot/config.txt
    sudo sed -i "s/^lcdrotate=.*/lcdrotate=0/g" /mnt/hdd/raspiblitz.conf

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

  else
    echo "error='missing second parameter - see help'"
    exit 1
  fi
  exit 0
fi

###################
# IMAGE
###################

if [ "${command}" == "image" ]; then
  
  imagePath=$2
  if [ ${#imagePath} -eq 0 ]; then
    echo "error='missing second parameter - see help'"
    exit 1
  else
    # test the image path - if file exists
    if [ -f "$imagePath" ]; then
      echo "# OK - file exists: ${imagePath}"
    else
      echo "error='file does not exist'"
      exit 1
    fi
  fi

  sudo fbi -a -T 1 -d /dev/fb1 --noverbose ${imagePath} 2> /dev/null
  exit 0
fi


###################
# QR CODE
###################

if [ "${command}" == "qr" ]; then

  datastring=$2
  if [ ${#datastring} -eq 0 ]; then
    echo "error='missing second parameter - see help'"
    exit 1
  fi

  qrencode -l L -o /home/admin/qr.png "${datastring}" > /dev/null
  sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/qr.png 2> /dev/null
  exit 0
fi

###################
# QR CODE KONSOLE
# fallback if no LCD is available
###################

if [ "${command}" == "qr-console" ]; then

  datastring=$2
  if [ ${#datastring} -eq 0 ]; then
    echo "error='missing second parameter - see help'"
    exit 1
  fi

  whiptail --title "Get ready" --backtitle "QR-Code in Terminal Window" \
    --msgbox "Make this terminal window as large as possible - fullscreen would be best. \n\nThe QR-Code might be too large for your display. In that case, shrink the letters by pressing the keys Ctrl and Minus (or Cmd and Minus if you are on a Mac) \n\nPRESS ENTER when you are ready to see the QR-code." 20 60

  clear
  qrencode -t ANSI256 ${datastring}
  echo "(To shrink QR code: macOS press CMD- / LINUX press CTRL-) Press ENTER when finished."
  read key

  clear
  exit 0
fi

###################
# HIDE
###################

if [ "${command}" == "hide" ]; then
  sudo killall -3 fbi
  shred /home/admin/qr.png 2> /dev/null
  rm -f /home/admin/qr.png 2> /dev/null
  exit 0
fi

###################
# HDMI
# see https://github.com/rootzoll/raspiblitz/issues/767
# see https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28A%29
###################

if [ "${command}" == "hdmi" ]; then

  # make sure that the config entry exists
  
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null| grep -c 'lcd2hdmi=') -eq 0 ]; then
    echo "lcd2hdmi=off" >> /mnt/hdd/raspiblitz.conf 2>/dev/null
  fi

  secondParameter=$2
  if [ "${secondParameter}" == "on" ]; then
    sudo sed -i 's/^lcd2hdmi=.*/lcd2hdmi=on/g' /home/admin/raspiblitz.info 2>/dev/null
    sudo sed -i 's/^lcd2hdmi=.*/lcd2hdmi=on/g' /mnt/hdd/raspiblitz.conf 2>/dev/null
    cd /home/admin/LCD-show
    ./LCD-hdmi
  elif [ "${secondParameter}" == "off" ]; then
    sudo sed -i 's/^lcd2hdmi=.*/lcd2hdmi=off/g' /home/admin/raspiblitz.info 2>/dev/null
    sudo sed -i 's/^lcd2hdmi=.*/lcd2hdmi=off/g' /mnt/hdd/raspiblitz.conf 2>/dev/null
    cd /home/admin/LCD-show
    ./LCD35-show
  else
    echo "error='unkown second parameter'"
    exit 1
  fi
  exit 0

fi

# unknown command
echo "error='unkown command'"
exit 1