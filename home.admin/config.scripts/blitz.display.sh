#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# make changes to the LCD screen"
  echo
  echo "# all commands need to run as root or with sudo"
  echo "# blitz.display.sh image [path]"
  echo "# blitz.display.sh qr [datastring]"
  echo "# blitz.display.sh qr-console [datastring]"
  echo "# blitz.display.sh hide"
  echo
  echo "# sudo blitz.display.sh rotate [on|off]"
  echo "# sudo blitz.display.sh test-lcd-connect"
  echo "# sudo blitz.display.sh set-display [hdmi|lcd|headless]"
  echo "# sudo blitz.display.sh prepare-install"
  exit 1
fi

# 1. Parameter: lcd command
command=$1
echo "### blitz.display.sh $command"

# its OK if its not exist yet
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# check if LCD (/dev/fb1) or HDMI (/dev/fb0)
# see https://github.com/rootzoll/raspiblitz/pull/1580
# but basically this just says if the driver for GPIO LCD is installed - not if connected
fb1Exists=$(ls /dev/fb1 2>/dev/null | grep -c "/dev/fb1")

# determine correct raspberrypi config files
raspi_configfile="/boot/config.txt"
raspi_commandfile="/boot/cmdline.txt"
if [ -d /boot/firmware ];then
  raspi_configfile="/boot/firmware/config.txt" 
  raspi_commandfile="/boot/firmware/cmdline.txt"
fi
echo "# raspi_configfile(${raspi_configfile})"
echo "# raspi_commandfile(${raspi_commandfile})"

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

###########################################################################
# All below here - needs to be run as root user or called with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
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
  if [ ${fb1Exists} -eq 1 ] ; then
    # LCD
    fbi -a -T 1 -d /dev/fb1 --noverbose ${imagePath} 2> /dev/null
  else
    # HDMI
    fbi -a -T 1 -d /dev/fb0 --noverbose ${imagePath} 2> /dev/null
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

  qrencode -l L -o /var/cache/raspiblitz/qr.png "${datastring}" > /dev/null
  # see https://github.com/rootzoll/raspiblitz/pull/1580
  if [ ${fb1Exists} -eq 1 ] ; then
    # LCD
    fbi -a -T 1 -d /dev/fb1 --noverbose /var/cache/raspiblitz/qr.png 2> /dev/null
  else
    # HDMI
    fbi -a -T 1 -d /dev/fb0 --noverbose /var/cache/raspiblitz/qr.png 2> /dev/null
  fi
  exit 0
fi

###################
# HIDE
###################

if [ "${command}" == "hide" ]; then
  killall -3 fbi
  rm /var/cache/raspiblitz/qr.png 2> /dev/null
  exit 0
fi

##################
# ROTATE
# see issue: https://github.com/rootzoll/raspiblitz/issues/681
###################

if [ "${command}" == "rotate" ]; then

  # TURN ROTATE ON (the new default)
  if [ "$2" = "1" ] || [ "$2" = "on" ]; then

    # change rotation config
    echo "# Turn ON: LCD ROTATE"
    sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=90/g" ${raspi_configfile}
    rm /etc/X11/xorg.conf.d/40-libinput.conf 2>/dev/null

    /home/admin/config.scripts/blitz.conf.sh set lcdrotate 1 1>/dev/null 2>/dev/null
    echo "# OK - a restart is needed: sudo shutdown -r now"

  # TURN ROTATE OFF
  elif [ "$2" = "0" ] || [ "$2" = "off" ]; then

    # change rotation config
    echo "#Turn OFF: LCD ROTATE"
    sed -i "s/^dtoverlay=.*/dtoverlay=waveshare35a:rotate=270/g" ${raspi_configfile}

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

    # update raspiblitz conf
    /home/admin/config.scripts/blitz.conf.sh set lcdrotate 0 1>/dev/null 2>/dev/null
    echo "OK - a restart is needed: sudo shutdown -r now"

  else
    echo "error='missing second parameter - see help'"
    exit 1
  fi
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

function prepareinstall() {
  repoCloned=$(sudo -u admin ls /home/admin/wavesharelcd-64bit-rpi/README.md 2>/dev/null| grep -c README.md)
  if [ ${repoCloned} -lt 1 ]; then
    echo "# clone/download https://github.com/tux1c/wavesharelcd-64bit-rpi.git"
    cd /home/admin/
    sudo -u admin git clone --no-checkout https://github.com/tux1c/wavesharelcd-64bit-rpi.git
    sudo -u admin chmod -R 755 wavesharelcd-64bit-rpi
    sudo -u admin chown -R admin:admin wavesharelcd-64bit-rpi
  else
    echo "# LCD repo already cloned/downloaded (${repoCloned})"
  fi
}

#######################################
# DISPLAY TYPED INSTALLS & UN-INSTALLS
# HDMI is the default - every added
# displayClass needs a install function
# and a uninstall function back to HDMI
#######################################

function install_hdmi() {
  echo "# hdmi install ... set framebuffer width/height"
  #sed -i "s/^#framebuffer_width=.*/framebuffer_width=480/g" ${raspi_configfile}
  #sed -i "s/^#framebuffer_height=.*/framebuffer_height=320/g" ${raspi_configfile}
}

function uninstall_hdmi() {
  echo "# hdmi uninstall ... reset framebuffer width/height"
  #sed -i "s/^framebuffer_width=.*/#framebuffer_width=480/g" ${raspi_configfile}
  #sed -i "s/^framebuffer_height=.*/#framebuffer_height=320/g" ${raspi_configfile}
}

function install_lcd() {

  if [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian_rpi64" ]; then

    echo "# INSTALL 64bit LCD DRIVER"

    # set font
    sed -i "s/^CHARMAP=.*/CHARMAP=\"UTF-8\"/" /etc/default/console-setup
    sed -i "s/^CODESET=.*/CODESET=\"guess\"/" /etc/default/console-setup 
    sed -i "s/^FONTFACE=.*/FONTFACE=\"TerminusBoldVGA\"/" /etc/default/console-setup
    sed -i "s/^FONTSIZE=.*/FONTSIZE=\"8x16\"/" /etc/default/console-setup 

    # hold bootloader
    sudo apt-mark hold raspberrypi-bootloader

    # Downloading LCD Driver from Github
    prepareinstall
    cd /home/admin/wavesharelcd-64bit-rpi
    sudo -u admin git checkout master
    sudo -u admin git reset --hard 5a206a7 || exit 1
    
    sudo -u admin /home/admin/config.scripts/blitz.git-verify.sh 'GitHub' 'https://github.com/web-flow.gpg' '(4AEE18F83AFDEB23|B5690EEEBB952194)' || exit 1

    # customized from https://github.com/tux1c/wavesharelcd-64bit-rpi/blob/master/install.sh
    rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
    mkdir -p /etc/X11/xorg.conf.d
    cp -rf ./99-calibration.conf  /etc/X11/xorg.conf.d/99-calibration.conf
    cp -rf ./99-fbturbo.conf  /etc/X11/xorg.conf.d/99-fbturbo.conf

    # add waveshare mod
    cp ./waveshare35a.dtbo /boot/overlays/

    # modify config file
    sed -i "s/^hdmi_force_hotplug=.*//g" ${raspi_configfile}
    sed -i '/^hdmi_group=/d' ${raspi_configfile} 2>/dev/null
    sed -i "/^hdmi_mode=/d" ${raspi_configfile} 2>/dev/null

    #sed -i "s/^#framebuffer_width=.*/framebuffer_width=480/g" ${raspi_configfile}
    #sed -i "s/^#framebuffer_height=.*/framebuffer_height=320/g" ${raspi_configfile}
    #echo "hdmi_force_hotplug=1" >> ${raspi_configfile}
    sed -i "s/^dtparam=i2c_arm=.*//g" ${raspi_configfile}
    # echo "dtparam=i2c_arm=on" >> ${raspi_configfile} --> this is to be called I2C errors - see: https://github.com/rootzoll/raspiblitz/issues/1058#issuecomment-739517713
    # don't enable SPI and UART ports by default
    # echo "dtparam=spi=on" >> ${raspi_configfile}
    # echo "enable_uart=1" >> ${raspi_configfile}
    sed -i "s/^dtoverlay=.*//g" ${raspi_configfile}
    echo "dtoverlay=waveshare35a:rotate=90" >> ${raspi_configfile}

    # modify cmdline.txt 
    modification="dwc_otg.lpm_enable=0 quiet fbcon=map:10 fbcon=font:ProFont6x11 logo.nologo"
    containsModification=$(grep -c "${modification}" ${raspi_commandfile})
    if [ ${containsModification} -eq 0 ]; then
      echo "# adding modification to ${raspi_commandfile}"
      cmdlineContent=$(cat ${raspi_commandfile})
      echo "${cmdlineContent} ${modification}" > ${raspi_commandfile}
    else
      echo "# ${raspi_commandfile} already contains modification"
    fi
    containsModification=$(grep -c "${modification}" ${raspi_commandfile})
    if [ ${containsModification} -eq 0 ]; then
      echo "# FAIL: was not able to modify ${raspi_commandfile}"
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
    setfont /usr/share/consolefonts/Uni3-TerminusBold16.psf.gz

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
    apt-mark hold raspberrypi-bootloader

    # make sure xinput-calibrator is installed
    apt-get install -y xinput-calibrator

    # remove modifications of config.txt
    sed -i '/^hdmi_force_hotplug=/d' ${raspi_configfile} 2>/dev/null
    sed -i '/^hdmi_group=/d' ${raspi_configfile} 2>/dev/null
    sed -i "/^hdmi_mode=/d" ${raspi_configfile} 2>/dev/null
    sed -i "s/^dtoverlay=.*//g" ${raspi_configfile} 2>/dev/null
    #sed -i "s/^framebuffer_width=.*/#framebuffer_width=480/g" ${raspi_configfile}
    #sed -i "s/^framebuffer_height=.*/#framebuffer_height=320/g" ${raspi_configfile}
    echo "hdmi_group=1" >> ${raspi_configfile}
    echo "hdmi_mode=3" >> ${raspi_configfile}
    echo "dtoverlay=pi3-disable-bt" >> ${raspi_configfile}
    echo "dtoverlay=disable-bt" >> ${raspi_configfile}

    # remove modification of cmdline.txt
    sed -i "s/ dwc_otg.lpm_enable=0 quiet fbcon=map:10 fbcon=font:ProFont6x11 logo.nologo//g" ${raspi_commandfile}

    # un-prepare X11
    mv /home/admin/wavesharelcd-64bit-rpi/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf 2>/dev/null
    rm -rf /etc/X11/xorg.conf.d/99-calibration.conf

    # remove github code of LCD drivers
    rm -r /home/admin/wavesharelcd-64bit-rpi

    echo "# OK uninstall LCD done ... reboot needed"

  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

function install_headless() {
  if [ "${baseimage}" = "raspios_arm64" ]|| [ "${baseimage}" = "debian_rpi64" ]; then
    modificationExists=$(cat /etc/systemd/system/getty@tty1.service.d/autologin.conf | grep -c "autologin pi")
    if [ "${modificationExists}" == "1" ]; then
      echo "# deactivating auto-login of pi user"
      # set Raspi to deactivate auto-login (will delete /etc/systemd/system/getty@tty1.service.d/autologin.conf)
      raspi-config nonint do_boot_behaviour B1
    else
      echo "# auto-login of pi user is already deactivated"
    fi
  elif [ "${baseimage}" = "dietpi" ]; then
    # TODO make switch between headless & HDMI possible
    echo "# TODO: reverse HDMI mode if set before"
    echo "# headless is already the default mode"
  elif [ "${baseimage}" = "ubuntu" ] || [ "${baseimage}" = "armbian" ]; then
    # TODO make switch between headless & HDMI possible
    echo "# TODO: reverse HDMI mode if set before"
    echo "# headless is already the default mode"
  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

function uninstall_headless() {
  if [ "${baseimage}" = "raspios_arm64" ] || [ "${baseimage}" = "debian_rpi64" ]; then
    # activate auto-login
    raspi-config nonint do_boot_behaviour B2
    modificationExists=$(cat /etc/systemd/system/getty@tty1.service.d/autologin.conf | grep -c "autologin pi")
    if [ "${modificationExists}" == "0" ]; then
      echo "# activating auto-login of pi user again"
      # set Raspi to boot up automatically with user pi
      # https://www.raspberrypi.org/forums/viewtopic.php?t=21632
      bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
    else
      echo "# auto-login of pi user already active"
    fi
   elif [ "${baseimage}" = "dietpi" ]; then
      # set DietPi to boot up automatically with user pi (for the LCD)
      # requires AUTO_SETUP_AUTOSTART_TARGET_INDEX=7 in the dietpi.txt
      # /DietPi/dietpi/dietpi-autostart overwrites /etc/systemd/system/getty@tty1.service.d/dietpi-autologin.conf on reboot
      sed -i 's/agetty --autologin root %I $TERM/agetty --autologin pi --noclear %I 38400 linux/' /DietPi/dietpi/dietpi-autostart
   elif [ "${baseimage}" = "ubuntu" ] || [ "${baseimage}" = "armbian" ]; then
      modificationExists=$(cat /lib/systemd/system/getty@.service | grep -c "autologin pi")
      if [ "${modificationExists}" == "0" ]; then
        bash -c "echo '[Service]' >> /lib/systemd/system/getty@.service"
        bash -c "echo 'ExecStart=' >> /lib/systemd/system/getty@.service"
        bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /lib/systemd/system/getty@.service"
      else
        echo "# auto-login of pi user already active"
      fi
  else
    echo "err='baseimage not supported'"
    exit 1
  fi
}

###################
# PREPARE INSTALL
# make sure github
# repo is installed
###################

if [ "${command}" == "prepare-install" ]; then
  prepareinstall
  exit 0
fi

###################
# SET DISPLAY TYPE
###################

if [ "${command}" == "set-display" ]; then

  paramDisplayClass=$2
  paramDisplayType=$3
  echo "# blitz.display.sh set-display ${paramDisplayClass} ${paramDisplayType}"
  echo "baseimage(${baseimage})"

  # check if started with sudo
  if [ "$EUID" -ne 0 ]; then 
    echo "error='missing sudo'"
    exit 1
  fi

  # abort if set to lcd and is vm
  if [ "${vm}" == "1" ] && [ "${paramDisplayClass}" == "lcd" ]; then
    echo "err='LCD not supported on VM'"
    exit 1
  fi

  # check if display class parameter is given
  if [ "${baseimage}" == "" ]; then
    echo "err='missing baseimage info'"
    exit 1
  fi

  # check if display class parameter is given
  if [ "${paramDisplayClass}" == "" ]; then
    echo "err='missing parameter'"
    exit 1
  fi

  # Make sure needed packages are installed
  if [ $(dpkg-query -l | grep "ii  fbi" | wc -l) = 0 ]; then
    sudo apt-get install fbi -y > /dev/null
  fi
  if [ $(dpkg-query -l | grep "ii  qrencode" | wc -l) = 0 ]; then
    sudo apt-get install qrencode -y > /dev/null
  fi

  echo "# old(${displayClass})"
  echo "# new(${paramDisplayClass})"

  if [ "${paramDisplayClass}" == "hdmi" ] || [ "${paramDisplayClass}" == "lcd" ] || [ "${paramDisplayClass}" == "headless" ]; then

    # uninstall old state
    uninstall_$displayClass

    # install new state
    install_$paramDisplayClass

  else
    echo "err='unknown parameter'"
    exit 1
  fi

  # mark new display class in config (if exist)
  /home/admin/config.scripts/blitz.conf.sh set displayClass ${paramDisplayClass} 2>/dev/null
  sed -i "s/^displayClass=.*/displayClass=${paramDisplayClass}/g" /home/admin/raspiblitz.info
  exit 0

fi

# unknown command
echo "error='unknown command'"
exit 1