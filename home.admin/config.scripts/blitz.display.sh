#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# make changes to the LCD screen"
  echo "# blitz.display.sh rotate [on|off]"
  echo "# blitz.display.sh image [path]"
  echo "# blitz.display.sh qr [datastring]"
  echo "# blitz.display.sh qr-console [datastring]"
  echo "# blitz.display.sh hide"
  echo "# blitz.display.sh hdmi [on|off] ---> DEPRECATED use set-display"
  echo "# blitz.display.sh test-lcd-connect"
  echo "# blitz.display.sh set-display [hdmi|lcd|headless]"
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

# check if LCD (/dev/fb1) or HDMI (/dev/fb0)
# see https://github.com/rootzoll/raspiblitz/pull/1580
# but basically this just says if the driver for GPIO LCD is installed - not if connected
lcdExists=$(sudo ls /dev/fb1 2>/dev/null | grep -c "/dev/fb1")

##################
# ROTATE
# see issue: https://github.com/rootzoll/raspiblitz/issues/681
###################

if [ "${command}" == "rotate" ]; then

  # TURN ROTATE ON (the new default)
  if [ "$2" = "1" ] || [ "$2" = "on" ]; then

    # add default 'lcdrotate' raspiblitz.conf if needed
    if [ ${#lcdrotate} -eq 0 ]; then
      echo "lcdrotate=0" >> /mnt/hdd/raspiblitz.conf
    fi

    # change rotation config
    echo "# Turn ON: LCD ROTATE"
    sudo sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=90/g" /boot/config.txt
    sudo rm /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null

    # update raspiblitz conf file
    sudo sed -i "s/^lcdrotate=.*/lcdrotate=1/g" /mnt/hdd/raspiblitz.conf
    echo "# OK - a restart is needed: sudo shutdown -r now"

  # TURN ROTATE OFF
  elif [ "$2" = "0" ] || [ "$2" = "off" ]; then

    # change rotation config
    echo "#Turn OFF: LCD ROTATE"
    sudo sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=270/g" /boot/config.txt

    # if touchscreen is on
    if [ "${touchscreen}" = "1" ]; then
      echo "# also rotate touchscreen ..."
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

    # update raspiblitz conf file
    sudo sed -i "s/^lcdrotate=.*/lcdrotate=0/g" /mnt/hdd/raspiblitz.conf
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

  # see https://github.com/rootzoll/raspiblitz/pull/1580
  if [ ${lcdExists} -eq 1 ] ; then
    # LCD
    sudo fbi -a -T 1 -d /dev/fb1 --noverbose ${imagePath} 2> /dev/null
  else
    # HDMI
    sudo fbi -a -T 1 -d /dev/fb0 --noverbose ${imagePath} 2> /dev/null
  fi
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
  # see https://github.com/rootzoll/raspiblitz/pull/1580
  if [ ${lcdExists} -eq 1 ] ; then
    # LCD
    sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/qr.png 2> /dev/null
  else
    # HDMI
    sudo fbi -a -T 1 -d /dev/fb0 --noverbose /home/admin/qr.png 2> /dev/null
  fi
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

  whiptail --title "Get ready" --backtitle "QR-Code in Terminal Window" --msgbox "Make this terminal window as large as possible - fullscreen would be best. \n\nThe QR-Code might be too large for your display. In that case, shrink the letters by pressing the keys Ctrl and Minus (or Cmd and Minus if you are on a Mac) \n\nPRESS ENTER when you are ready to see the QR-code." 15 60

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
  shred -u /home/admin/qr.png 2> /dev/null
  exit 0
fi

###################
# TEST LCD CONNECT
# only tested on RaspiOS 64-bit with RaspberryPi 4
# https://github.com/rootzoll/raspiblitz/issues/1265#issuecomment-813660030
###################

if [ "${command}" == "test-lcd-connect" ]; then
  echo "# IMPORTANT --> just gives correct value first time called after boot"
  source <(sudo python /home/admin/config.scripts/blitz.gpio.py in 17)
  if [ "${pinValue}" == "1" ]; then
    echo "gpioLcdConnected=1"
  elif [ "${pinValue}" == "0" ]; then
    echo "gpioLcdConnected=0"
  else
    echo "# FAIL: only works on raspiOS 64-bit & RaspberryPi 4"
    echo "# test directly with --> sudo python /home/admin/config.scripts/blitz.gpio.py in 17"
    echo "err='detection not possible'"
    exit 1
  fi
   exit 0
fi

###############################
# HDMI (deprecated - redirect)
###############################
if [ "${command}" == "hdmi" ]; then
  secondParameter=$2
  if [ "${secondParameter}" == "on" ]; then
    sudo /home/admin/config.scripts/blitz.display.sh set-display hdmi
  elif [ "${secondParameter}" == "off" ]; then
    sudo /home/admin/config.scripts/blitz.display.sh set-display lcd
  else
    echo "error='unkown second parameter'"
    exit 1
  fi
  exit 0
fi

#######################################
# DISPLAY TYPED INSTALLS & UN-INSTALLS
# HDMI is the default - every added
# displayClass needs a install fuction
# and a uninstall function back to HDMI
#######################################

function install_hdmi() {
  echo "# nothing to install - hdmi is the default/clean mode"
}

function uninstall_hdmi() {
  echo "# nothing to uninstall - hdmi is the default/clean mode"
}

function install_lcd() {

  if [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian_rpi64" ]; then

    echo "# INSTALL 64bit LCD DRIVER"

    # hold bootloader
    sudo apt-mark hold raspberrypi-bootloader

    # Downloading LCD Driver from Github
    cd /home/admin/
    sudo -u admin git clone https://github.com/tux1c/wavesharelcd-64bit-rpi.git
    sudo -u admin chmod -R 755 wavesharelcd-64bit-rpi
    sudo -u admin chown -R admin:admin wavesharelcd-64bit-rpi
    cd /home/admin/wavesharelcd-64bit-rpi
    sudo -u admin git reset --hard 5a206a7 || exit 1

    # customized from https://github.com/tux1c/wavesharelcd-64bit-rpi/blob/master/install.sh
    # prepare X11
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo mv /etc/X11/xorg.conf.d/40-libinput.conf /home/admin/wavesharelcd-64bit-rpi/40-libinput.conf 2>/dev/null
    sudo cp -rf ./99-calibration.conf /etc/X11/xorg.conf.d/99-calibration.conf
    # sudo cp -rf ./99-fbturbo.conf  /etc/X11/xorg.conf.d/99-fbturbo.conf # there is no such file

    # add waveshare mod
    sudo cp ./waveshare35a.dtbo /boot/overlays/

    # modify /boot/config.txt 
    sudo sed -i "s/^hdmi_force_hotplug=.*//g" /boot/config.txt 
    echo "hdmi_force_hotplug=1" >> /boot/config.txt
    sudo sed -i "s/^dtparam=i2c_arm=.*//g" /boot/config.txt 
    # echo "dtparam=i2c_arm=on" >> /boot/config.txt --> this is to be called I2C errors - see: https://github.com/rootzoll/raspiblitz/issues/1058#issuecomment-739517713
    # don't enable SPI and UART ports by default
    # echo "dtparam=spi=on" >> /boot/config.txt
    # echo "enable_uart=1" >> /boot/config.txt
    sudo sed -i "s/^dtoverlay=.*//g" /boot/config.txt 
    echo "dtoverlay=waveshare35a:rotate=90" >> /boot/config.txt

    # modify cmdline.txt 
    modification="dwc_otg.lpm_enable=0 quiet fbcon=map:10 fbcon=font:ProFont6x11 logo.nologo"
    containsModification=$(sudo grep -c "${modification}" /boot/cmdline.txt)
    if [ ${containsModification} -eq 0 ]; then
      echo "# adding modification to /boot/cmdline.txt"
      cmdlineContent=$(sudo cat /boot/cmdline.txt)
      echo "${cmdlineContent} ${modification}" > /boot/cmdline.txt
    else
      echo "# /boot/cmdline.txt already contains modification"
    fi
    containsModification=$(sudo grep -c "${modification}" /boot/cmdline.txt)
    if [ ${containsModification} -eq 0 ]; then
      echo "# FAIL: was not able to mofify /boot/cmdline.txt"
      echo "err='ended unclear state'"
      exit 1
    fi

    # touch screen calibration
    apt-get install -y xserver-xorg-input-evdev
    cp -rf /usr/share/X11/xorg.conf.d/10-evdev.conf /usr/share/X11/xorg.conf.d/45-evdev.conf
    # TODO manual touchscreen calibration option
    # https://github.com/tux1c/wavesharelcd-64bit-rpi#adapting-guide-to-other-lcds

    # set font that fits the LCD screen
    # https://github.com/rootzoll/raspiblitz/issues/244#issuecomment-476713706
    # there can be a different font for different types of LCDs with using the displayType parameter in the future
    sudo setfont /usr/share/consolefonts/Uni3-TerminusBold16.psf.gz

    echo "# OK install of LCD done ... reboot needed"

  else
    echo "err='baseimage not supported'"
    exit 1
  fi

}

function uninstall_lcd() {

  if [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian_rpi64" ]; then

    echo "# UNINSTALL 64bit LCD DRIVER"

    # hold bootloader
    sudo apt-mark hold raspberrypi-bootloader

    # make sure xinput-calibrator is installed
    sudo apt-get install -y xinput-calibrator

    # remove modifications of config.txt
    sudo sed -i "s/^hdmi_force_hotplug=.*//g" /boot/config.txt 
    sudo sed -i "s/^dtoverlay=.*//g" /boot/config.txt 
    echo "dtoverlay=pi3-disable-bt" >> /boot/config.txt
    echo "dtoverlay=disable-bt" >> /boot/config.txt

    # remove modification of cmdline.txt
    sudo sed -i "s/ dwc_otg.lpm_enable=0 quiet fbcon=map:10 fbcon=font:ProFont6x11 logo.nologo//g" /boot/cmdline.txt

    # un-prepare X11
    sudo mv /home/admin/wavesharelcd-64bit-rpi/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf 2>/dev/null
    sudo rm -rf /etc/X11/xorg.conf.d/99-calibration.conf

    # remove github code of LCD drivers
    sudo rm -r /home/admin/wavesharelcd-64bit-rpi

    echo "# OK uninstall LCD done ... reboot needed"

  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

# not being used - can be deleted after mid 2021
function install_lcd_legacy() {

  if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "dietpi" ]; then
    echo "*** 32bit LCD DRIVER ***"
    echo "--> Downloading LCD Driver from Github"
    cd /home/admin/
    sudo -u admin git clone https://github.com/MrYacha/LCD-show.git
    sudo -u admin chmod -R 755 LCD-show
    sudo -u admin chown -R admin:admin LCD-show
    cd LCD-show/
    sudo -u admin git reset --hard 53dd0bf || exit 1
    # install xinput calibrator package
    echo "--> install xinput calibrator package"
    sudo apt install -y libxi6
    sudo dpkg -i xinput-calibrator_0.7.5-1_armhf.deb
 
    if [ "${baseimage}" = "dietpi" ]; then
      echo "--> dietpi preparations"
      sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
      sudo mkdir /etc/X11/xorg.conf.d
      sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/
      sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/tft35a.dtbo
      sudo cp -rf ./usr/99-calibration.conf-35  /etc/X11/xorg.conf.d/99-calibration.conf
      sudo cp -rf ./usr/99-fbturbo.conf  /usr/share/X11/xorg.conf.d/
      sudo cp ./usr/cmdline.txt /DietPi/
      sudo cp ./usr/inittab /etc/
      sudo cp ./boot/config-35.txt /DietPi/config.txt
      # make LCD screen rotation correct
      sudo sed -i "s/dtoverlay=tft35a/dtoverlay=tft35a:rotate=270/" /DietPi/config.txt
    fi
  elif [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian_rpi64" ]; then
    echo "*** 64bit LCD DRIVER ***"
    echo "--> Downloading LCD Driver from Github"
    cd /home/admin/
    sudo -u admin git clone https://github.com/tux1c/wavesharelcd-64bit-rpi.git
    sudo -u admin chmod -R 755 wavesharelcd-64bit-rpi
    sudo -u admin chown -R admin:admin wavesharelcd-64bit-rpi
    cd /home/admin/wavesharelcd-64bit-rpi
    sudo -u admin git reset --hard 5a206a7 || exit 1

    # from https://github.com/tux1c/wavesharelcd-64bit-rpi/blob/master/install.sh
    # prepare X11
    sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo cp -rf ./99-calibration.conf /etc/X11/xorg.conf.d/99-calibration.conf
    # sudo cp -rf ./99-fbturbo.conf  /etc/X11/xorg.conf.d/99-fbturbo.conf # there is no such file

    # add waveshare mod
    sudo cp ./waveshare35a.dtbo /boot/overlays/

    # modify /boot/config.txt 
    sudo sed -i "s/^hdmi_force_hotplug=.*//g" /boot/config.txt 
    echo "hdmi_force_hotplug=1" >> /boot/config.txt
    sudo sed -i "s/^dtparam=i2c_arm=.*//g" /boot/config.txt 
    echo "dtparam=i2c_arm=on" >> /boot/config.txt
    # don't enable SPI and UART ports by default
    # echo "dtparam=spi=on" >> /boot/config.txt
    # echo "enable_uart=1" >> /boot/config.txt
    sudo sed -i "s/^dtoverlay=.*//g" /boot/config.txt 
    echo "dtoverlay=waveshare35a:rotate=90" >> /boot/config.txt

    # use modified cmdline.txt 
    sudo cp ./cmdline.txt /boot/

    # touch screen calibration
    apt-get install -y xserver-xorg-input-evdev
    cp -rf /usr/share/X11/xorg.conf.d/10-evdev.conf /usr/share/X11/xorg.conf.d/45-evdev.conf
    # TODO manual touchscreen calibration option
    # https://github.com/tux1c/wavesharelcd-64bit-rpi#adapting-guide-to-other-lcds
  fi

  # activate LCD and trigger reboot
  # dont do this on dietpi to allow for automatic build
  if [ "${baseimage}" = "raspbian" ]; then
    echo "Installing 32-bit LCD drivers ..."
    sudo chmod +x -R /home/admin/LCD-show
    cd /home/admin/LCD-show/
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./LCD35-show
  elif [ "${baseimage}" = "raspios_arm64" ] || [ "${baseimage}" = "debian_rpi64" ]; then
    echo "Installing 64-bit LCD drivers ..."
    sudo chmod +x -R /home/admin/wavesharelcd-64bit-rpi
    cd /home/admin/wavesharelcd-64bit-rpi
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./install.sh
  else
    echo "Use 'sudo reboot' to restart manually."
  fi

}

function install_headless() {
  if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64" ]|| [ "${baseimage}" = "debian_rpi64" ]; then
    modificationExists=$(sudo cat /etc/systemd/system/getty@tty1.service.d/autologin.conf | grep -c "autologin pi")
    if [ "${modificationExists}" == "1" ]; then
      echo "# deactivating auto-login of pi user"
      # set Raspi to deactivate auto-login (will delete /etc/systemd/system/getty@tty1.service.d/autologin.conf)
      sudo raspi-config nonint do_boot_behaviour B1
    else
      echo "# auto-login of pi user is already deactivated"
    fi
  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

function uninstall_headless() {
  if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64" ]|| [ "${baseimage}" = "debian_rpi64" ]; then
    modificationExists=$(sudo cat /etc/systemd/system/getty@tty1.service.d/autologin.conf | grep -c "autologin pi")
    if [ "${modificationExists}" == "0" ]; then
      echo "# activating auto-login of pi user again"
      # set Raspi to boot up automatically with user pi (for the LCD)
      # https://www.raspberrypi.org/forums/viewtopic.php?t=21632
      sudo raspi-config nonint do_boot_behaviour B2
      sudo bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      sudo bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
    else
      echo "# auto-login of pi user already active"
    fi
  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

function prepareDisplayClassEntryRaspiblitzConf() {
  # check if file exists / hdd is mounted
  if [ -f "/mnt/hdd/raspiblitz.conf" ]; then
    echo "file does exists"
    entryExists=$(grep -c "displayClass=" /mnt/hdd/raspiblitz.conf)
    if [ ${entryExists} -eq 0 ]; then
      echo "displayClass=${displayClass}" >> /mnt/hdd/raspiblitz.conf
    fi
  else
    echo "# /mnt/hdd/raspiblitz.conf does not exists (yet) - change is just part of raspiblitz.info"
  fi
}

###################
# SET DISPLAY TYPE
###################

if [ "${command}" == "set-display" ]; then

  paramDisplayClass=$2
  paramDisplayType=$3
  echo "# blitz.display.sh set-display ${paramDisplayClass} ${paramDisplayType}"

  # check if started with sudo
  if [ "$EUID" -ne 0 ]; then 
    echo "error='missing sudo'"
    exit 1
  fi

  if [ "${paramDisplayClass}" == "" ]; then
    echo "err='missing parameter'"
    exit 1
  elif [ "${paramDisplayClass}" == "${displayClass}" ]; then

    # normally dont make any changes here - but it can be the case that this called by recover/update process
    # where raspiblitz.info (base image) raspiblitz.conf (user config) have different values - check fo this case:
    confAndInfoValueIsSame=$(sudo cat /home/admin/raspiblitz.info | grep -c "displayClass=${paramDisplayClass}}")
    if [ "${confAndInfoValueIsSame}" == "0" ]; then
      echo "# raspiblitz.info is different from raspiblitz.conf --> enforcing ${displayClass} for both"
      source /home/admin/raspiblitz.info
      # continue with the raspiblitz.info value of displayClass as actual state (not the overwritten one from raspiblitz.conf)
    else
      echo "# raspiblitz.info (AND raspiblitz.conf) already running ${displayClass} - no need for change"
      exit 1
    fi
  fi
  if [ "${paramDisplayClass}" == "hdmi" ] || [ "${paramDisplayClass}" == "lcd" ] || [ "${paramDisplayClass}" == "headless" ]; then

    # uninstall old state
    uninstall_$displayClass

    # install new state
    install_$paramDisplayClass

  else
    echo "err='unknown parameter'"
    exit 1
  fi

  # mark new display class in configs
  prepareDisplayClassEntryRaspiblitzConf
  sudo sed -i "s/^displayClass=.*/displayClass=${paramDisplayClass}/g" /home/admin/raspiblitz.info
  sudo sed -i "s/^displayClass=.*/displayClass=${paramDisplayClass}/g" /mnt/hdd/raspiblitz.conf 2>/dev/null
  exit 0

fi

# unknown command
echo "error='unkown command'"
exit 1