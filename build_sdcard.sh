#!/bin/bash
#########################################################################
# Build your SD card image based on:
# raspios_arm64-2020-08-24
# https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2020-08-24/
# SHA256: 6ce59adc2b432f4a6c0a8827041b472b837c4f165ab7751fdc35f2d1c3ac518c
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script:
##########################################################################

echo ""
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP v1.7   *"
echo "*****************************************"
echo "For details on optional parameters - see build script source code:"

# 1st optional paramater: FATPACK
# -------------------------------
# could be 'true' or 'false' (default)
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...

fatpack="$1"
if [ ${#fatpack} -eq 0 ]; then
  fatpack="false"
fi
if [ "${fatpack}" != "true" ] && [ "${fatpack}" != "false" ]; then
  echo "ERROR: FATPACK parameter needs to be either 'true' or 'false'"
  exit 1
else
  echo "1) will use FATPACK --> '${fatpack}'"
fi

# 2st optional paramater: GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblitz repo - 'rootzoll' is default
# The 'raspiblitz' repo of this user is used to provisioning sd card 
# with raspiblitz assets/scripts later on.
# If this parameter is set also the branch needs to be given (see next parameter).
githubUser="$2"
if [ ${#githubUser} -eq 0 ]; then
  githubUser="rootzoll"
fi
echo "2) will use GITHUB-USERNAME --> '${githubUser}'"

# 3rd optional paramater: GITHUB-BRANCH
# -------------------------------------
# could be any valid branch of the given GITHUB-USERNAME forked raspiblitz repo - 'dev' is default
githubBranch="$3"
if [ ${#githubBranch} -eq 0 ]; then
  githubBranch="dev"
fi
echo "3) will use GITHUB-BRANCH --> '${githubBranch}'"

# 4rd optional paramater: LCD-DRIVER
# ----------------------------------------
# could be 'false' or 'GPIO' (default)
# Use 'false' if you want to build an image that runs without a specialized LCD (like the GPIO).
# On 'false' the standard video output is used (HDMI) by default.
lcdInstalled="$4"
if [ ${#lcdInstalled} -eq 0 ] || [ "${lcdInstalled}" == "true" ]; then
  lcdInstalled="GPIO"
fi
if [ "${lcdInstalled}" != "false" ] && [ "${lcdInstalled}" != "GPIO" ]; then
  echo "ERROR: LCD-DRIVER parameter needs to be either 'false' or 'GPIO'"
  exit 1
else
  echo "4) will use LCD-DRIVER --> '${lcdInstalled}'"
fi

# 5rd optional paramater: TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
tweakBootdrives="$5"
if [ ${#tweakBootdrives} -eq 0 ]; then
  tweakBootdrives="true"
fi
if [ "${tweakBootdrives}" != "true" ] && [ "${tweakBootdrives}" != "false" ]; then
  echo "ERROR: TWEAK-BOOTDRIVE parameter needs to be either 'true' or 'false'"
  exit 1
else
  echo "5) will use TWEAK-BOOTDRIVE --> '${tweakBootdrives}'"
fi

# 6rd optional paramater: WIFI
# ---------------------------------------
# could be 'false' or 'true' (default) or a valid WIFI country code like 'US' (default)
# If 'false' WIFI will be deactivated by default
# If 'true' WIFI will be activated by with default country code 'US'
# If any valid wifi country code Wifi will be activated with that country code by default
modeWifi="$6"
if [ ${#modeWifi} -eq 0 ] || [ "${modeWifi}" == "true" ]; then
  modeWifi="US"
fi
echo "6) will use WIFI --> '${modeWifi}'"

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
cpu="?"
if [ ${isARM} -gt 0 ]; then
  cpu="arm"
elif [ ${isAARCH64} -gt 0 ]; then
  cpu="aarch64"
elif [ ${isX86_64} -gt 0 ]; then
  cpu="x86_64"
else
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 not on:"
  uname -m
  exit 1
fi
echo "X) will use CPU-ARCHITECTURE --> '${cpu}'"

# AUTO-DETECTION: OPERATINGSYSTEM
# ---------------------------------------
baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
isDebian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
isNvidia=$(uname -a | grep -c 'tegra')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
fi
if [ ${isDebian} -gt 0 ]; then
  if [ $(uname -n | grep -c 'rpi') -gt 0 ] && [ ${isAARCH64} -gt 0 ]; then
    baseImage="debian_rpi64"
  elif [ $(uname -n | grep -c 'raspberrypi') -gt 0 ] && [ ${isAARCH64} -gt 0 ]; then
    baseImage="raspios_arm64"
  elif [ ${isAARCH64} -gt 0 ] || [ ${isARM} -gt 0 ] ; then
    baseImage="armbian"
  else
    baseImage="debian"
  fi
fi
if [ ${isUbuntu} -gt 0 ]; then
  baseImage="ubuntu"
fi
if [ ${isDietPi} -gt 0 ]; then
  baseImage="dietpi"
fi
if [ "${baseImage}" = "?" ]; then
  cat /etc/os-release 2>/dev/null
  echo "!!! FAIL: Base Image cannot be detected or is not supported."
  exit 1
fi
echo "X) will use OPERATINGSYSTEM ---> '${baseImage}'"

# USER-CONFIRMATION
echo -n "Do you agree with all parameters above? (yes/no) "
read installRaspiblitzAnswer
if [ "$installRaspiblitzAnswer" == "yes" ] ; then
  echo ""
  echo ""
  echo "Building RaspiBlitz ..."
  sleep 3
  echo ""
else
  exit 1
fi

# INSTALL TOR
echo "*** INSTALL TOR BY DEFAULT ***"
echo ""
sudo apt install -y dirmngr
echo "*** Adding KEYS deb.torproject.org ***"
# fix for v1.6 base image https://github.com/rootzoll/raspiblitz/issues/1906#issuecomment-755299759
wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
torKeyAvailable=$(sudo gpg --list-keys | grep -c "A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89")
if [ ${torKeyAvailable} -eq 0 ]; then
  echo "!!! FAIL: Was not able to import deb.torproject.org key"
  exit 1
fi
echo "- OK key added"

echo "*** Adding Tor Sources to sources.list ***"
torSourceListAvailable=$(sudo cat /etc/apt/sources.list | grep -c 'https://deb.torproject.org/torproject.org')
echo "torSourceListAvailable=${torSourceListAvailable}"  
if [ ${torSourceListAvailable} -eq 0 ]; then
  echo "- adding TOR sources ..."
  if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspios_arm64" ] || [ "${baseImage}" = "armbian" ] || [ "${baseImage}" = "dietpi" ]; then
    echo "- using https://deb.torproject.org/torproject.org buster"
    echo "deb https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
    echo "deb-src https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
  elif [ "${baseImage}" = "ubuntu" ]; then
    echo "- using https://deb.torproject.org/torproject.org focal"
    echo "deb https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list
    echo "deb-src https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list    
  else
    echo "!!! FAIL: No Tor sources for os: ${baseImage}"
    exit 1
  fi
  echo "- OK sources added"
else
  echo "TOR sources are available"
fi

echo "*** Install & Enable Tor ***"
sudo apt install tor tor-arm torsocks -y
echo ""

# FIXING LOCALES
# https://github.com/rootzoll/raspiblitz/issues/138
# https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
# https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "dietpi" ] || \
   [ "${baseImage}" = "raspios_arm64" ]||[ "${baseImage}" = "debian_rpi64" ]; then
  echo ""
  echo "*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=en_US.UTF-8
  export LANG=en_US.UTF-8
  if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "dietpi" ]; then
    export LC_ALL=en_US.UTF-8

    # https://github.com/rootzoll/raspiblitz/issues/684
    sudo sed -i "s/^    SendEnv LANG LC.*/#   SendEnv LANG LC_*/g" /etc/ssh/ssh_config

    # remove unneccesary files
    sudo rm -rf /home/pi/MagPi
    # https://www.reddit.com/r/linux/comments/lbu0t1/microsoft_repo_installed_on_all_raspberry_pis/
    sudo rm -f /etc/apt/sources.list.d/vscode.list 
    sudo rm -f /etc/apt/trusted.gpg.d/microsoft.gpg
  fi
  if [ ! -f /etc/apt/sources.list.d/raspi.list ]; then
    echo "# Add the archive.raspberrypi.org/debian/ to the sources.list"
    echo "deb http://archive.raspberrypi.org/debian/ buster main" | sudo tee /etc/apt/sources.list.d/raspi.list
  fi
fi

# remove some (big) packages that are not needed
sudo apt remove -y --purge libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi minecraft-pi plymouth python2 vlc
sudo apt clean
sudo apt -y autoremove

if [ -f "/usr/bin/python3.7" ]; then
  # make sure /usr/bin/python exists (and calls Python3.7 in Buster)
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.7 1
  echo "python calls python3.7"
elif [ -f "/usr/bin/python3.8" ]; then
  # use python 3.8 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  sudo ln -s /usr/bin/python3.8 /usr/bin/python3.7
  echo "python calls python3.8"
else
  echo "!!! FAIL !!!"
  echo "There is no tested version of python present"
  exit 1
fi

# update debian
echo ""
echo "*** UPDATE ***"
sudo apt update -y
sudo apt upgrade -f -y

echo ""
echo "*** PREPARE ${baseImage} ***"

# make sure the pi user is present
if [ "$(compgen -u | grep -c dietpi)" -gt 0 ];then
  echo "# Renaming dietpi user to pi"
  sudo usermod -l pi dietpi
elif [ "$(compgen -u | grep -c pi)" -eq 0 ];then  
  echo "# Adding the user pi"
  sudo adduser --disabled-password --gecos "" pi
  sudo adduser pi sudo
fi

# special prepare when Raspbian
if [ "${baseImage}" = "raspbian" ]||[ "${baseImage}" = "raspios_arm64" ]||\
   [ "${baseImage}" = "debian_rpi64" ]; then
  sudo apt install -y raspi-config 
  # do memory split (16MB)
  sudo raspi-config nonint do_memory_split 16
  # set to wait until network is available on boot (0 seems to yes)
  sudo raspi-config nonint do_boot_wait 0
  # set WIFI country so boot does not block
  if [ "${modeWifi}" != "false" ]; then
    # this will undo the softblock of rfkill on RaspiOS
    sudo raspi-config nonint do_wifi_country $modeWifi
  fi
  # see https://github.com/rootzoll/raspiblitz/issues/428#issuecomment-472822840

  configFile="/boot/config.txt"
  max_usb_current="max_usb_current=1"
  max_usb_currentDone=$(cat $configFile|grep -c "$max_usb_current")

  if [ ${max_usb_currentDone} -eq 0 ]; then
    sudo echo "" >> $configFile
    sudo echo "# Raspiblitz" >> $configFile
    echo "$max_usb_current" | sudo tee -a $configFile
  else
    echo "$max_usb_current already in $configFile"
  fi

  # run fsck on sd root partition on every startup to prevent "maintenance login" screen
  # see: https://github.com/rootzoll/raspiblitz/issues/782#issuecomment-564981630
  # see https://github.com/rootzoll/raspiblitz/issues/1053#issuecomment-600878695
  # use command to check last fsck check: sudo tune2fs -l /dev/mmcblk0p2
  if [ "${tweakBootdrives}" == "true" ]; then
    echo "* running tune2fs"
    sudo tune2fs -c 1 /dev/mmcblk0p2
  else
    echo "* skipping tweakBootdrives"
  fi

  # edit kernel parameters
  kernelOptionsFile=/boot/cmdline.txt
  fsOption1="fsck.mode=force"
  fsOption2="fsck.repair=yes"
  fsOption1InFile=$(cat ${kernelOptionsFile}|grep -c ${fsOption1})
  fsOption2InFile=$(cat ${kernelOptionsFile}|grep -c ${fsOption2})

  if [ ${fsOption1InFile} -eq 0 ]; then
    sudo sed -i "s/^/$fsOption1 /g" "$kernelOptionsFile"
    echo "$fsOption1 added to $kernelOptionsFile"
  else
    echo "$fsOption1 already in $kernelOptionsFile"
  fi
  if [ ${fsOption2InFile} -eq 0 ]; then
    sudo sed -i "s/^/$fsOption2 /g" "$kernelOptionsFile"
    echo "$fsOption2 added to $kernelOptionsFile"
  else
    echo "$fsOption2 already in $kernelOptionsFile"
  fi
fi

# special prepare when Nvidia Jetson Nano
if [ ${isNvidia} -eq 1 ] ; then
  # disable GUI on boot
  sudo systemctl set-default multi-user.target
fi

echo ""
echo "*** CONFIG ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#raspi-config

# set new default password for root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

if [ "${lcdInstalled}" != "false" ]; then
   if [ "${baseImage}" = "raspbian" ]||[ "${baseImage}" = "raspios_arm64" ]||\
      [ "${baseImage}" = "debian_rpi64" ]; then
      # set Raspi to boot up automatically with user pi (for the LCD)
      # https://www.raspberrypi.org/forums/viewtopic.php?t=21632
      sudo raspi-config nonint do_boot_behaviour B2
      sudo bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      sudo bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
      sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
   fi

   if [ "${baseImage}" = "dietpi" ]; then
      # set DietPi to boot up automatically with user pi (for the LCD)
      # requires AUTO_SETUP_AUTOSTART_TARGET_INDEX=7 in the dietpi.txt
      # /DietPi/dietpi/dietpi-autostart overwrites /etc/systemd/system/getty@tty1.service.d/dietpi-autologin.conf on reboot
      sudo sed -i 's/agetty --autologin root %I $TERM/agetty --autologin pi --noclear %I 38400 linux/' /DietPi/dietpi/dietpi-autostart
   fi

   if [ "${baseImage}" = "ubuntu" ] || [ "${baseImage}" = "armbian" ]; then
      sudo bash -c "echo '[Service]' >> /lib/systemd/system/getty@.service"
      sudo bash -c "echo 'ExecStart=' >> /lib/systemd/system/getty@.service"
      sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /lib/systemd/system/getty@.service"
   fi
fi

# change log rotates
# see https://github.com/rootzoll/raspiblitz/issues/394#issuecomment-471535483
echo "/var/log/syslog" >> ./rsyslog
echo "{" >> ./rsyslog
echo "	rotate 7" >> ./rsyslog
echo "	daily" >> ./rsyslog
echo "	missingok" >> ./rsyslog
echo "	notifempty" >> ./rsyslog
echo "	delaycompress" >> ./rsyslog
echo "	compress" >> ./rsyslog
echo "	postrotate" >> ./rsyslog
echo "		invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "	endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/mail.info" >> ./rsyslog
echo "/var/log/mail.warn" >> ./rsyslog
echo "/var/log/mail.err" >> ./rsyslog
echo "/var/log/mail.log" >> ./rsyslog
echo "/var/log/daemon.log" >> ./rsyslog
echo "{" >> ./rsyslog
echo "        rotate 4" >> ./rsyslog
echo "        size=100M" >> ./rsyslog
echo "        missingok" >> ./rsyslog
echo "        notifempty" >> ./rsyslog
echo "        compress" >> ./rsyslog
echo "        delaycompress" >> ./rsyslog
echo "        sharedscripts" >> ./rsyslog
echo "        postrotate" >> ./rsyslog
echo "                invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "        endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/kern.log" >> ./rsyslog
echo "/var/log/auth.log" >> ./rsyslog
echo "{" >> ./rsyslog
echo "        rotate 4" >> ./rsyslog
echo "        size=100M" >> ./rsyslog
echo "        missingok" >> ./rsyslog
echo "        notifempty" >> ./rsyslog
echo "        compress" >> ./rsyslog
echo "        delaycompress" >> ./rsyslog
echo "        sharedscripts" >> ./rsyslog
echo "        postrotate" >> ./rsyslog
echo "                invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "        endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/user.log" >> ./rsyslog
echo "/var/log/lpr.log" >> ./rsyslog
echo "/var/log/cron.log" >> ./rsyslog
echo "/var/log/debug" >> ./rsyslog
echo "/var/log/messages" >> ./rsyslog
echo "{" >> ./rsyslog
echo "	rotate 4" >> ./rsyslog
echo "	weekly" >> ./rsyslog
echo "	missingok" >> ./rsyslog
echo "	notifempty" >> ./rsyslog
echo "	compress" >> ./rsyslog
echo "	delaycompress" >> ./rsyslog
echo "	sharedscripts" >> ./rsyslog
echo "	postrotate" >> ./rsyslog
echo "		invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "	endscript" >> ./rsyslog
echo "}" >> ./rsyslog
sudo mv ./rsyslog /etc/logrotate.d/rsyslog
sudo chown root:root /etc/logrotate.d/rsyslog
sudo service rsyslog restart

echo ""
echo "*** SOFTWARE UPDATE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#software-update

# installs like on RaspiBolt
sudo apt install -y htop git curl bash-completion vim jq dphys-swapfile bsdmainutils

# installs bandwidth monitoring for future statistics
sudo apt install -y vnstat

# prepare for format data drive
sudo apt install -y parted dosfstools

# prepare for BTRFS data drive raid
sudo apt install -y btrfs-progs

# network tools
sudo apt install -y autossh telnet

# prepare for display graphics mode
# see https://github.com/rootzoll/raspiblitz/pull/334
sudo apt install -y fbi

# prepare for powertest
sudo apt install -y sysbench

# check for dependencies on DietPi, Ubuntu, Armbian
sudo apt install -y build-essential

# add armbian-config
if [ "${baseImage}" = "armbian" ]; then
  # add armbian config
  sudo apt install armbian-config -y
fi

# dependencies for python
sudo apt install -y python3-venv python3-dev python3-wheel python3-jinja2 python3-pip

# make sure /usr/bin/pip exists (and calls pip3 in Debian Buster)
sudo update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# rsync is needed to copy from HDD
sudo apt install -y rsync
# install ifconfig
sudo apt install -y net-tools
#to display hex codes
sudo apt install -y xxd
# setuptools needed for Nyx
sudo pip install setuptools
# netcat for 00infoBlitz.sh
sudo apt install -y netcat
# install OpenSSH client + server
sudo apt install -y openssh-client
sudo apt install -y openssh-sftp-server
sudo apt install -y sshpass
# install killall, fuser
sudo apt install -y psmisc
# install firewall
sudo apt install -y ufw


sudo apt clean
sudo apt -y autoremove

echo ""
echo "*** ADDING MAIN USER admin ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-main-user-admin
# using the default password 'raspiblitz'

sudo adduser --disabled-password --gecos "" admin
echo "admin:raspiblitz" | sudo chpasswd
sudo adduser admin sudo
sudo chsh admin -s /bin/bash

# configure sudo for usage without password entry
echo '%sudo ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo

echo ""
echo "*** ADDING SERVICE USER bitcoin"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-the-service-user-bitcoin

# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd

echo ""
echo "*** ADDING GROUPS FOR CREDENTIALS STORE ***"
# access to credentials (e.g. macaroon files) in a central location is managed with unix groups and permissions
sudo /usr/sbin/groupadd --force --gid 9700 lndadmin
sudo /usr/sbin/groupadd --force --gid 9701 lndinvoice
sudo /usr/sbin/groupadd --force --gid 9702 lndreadonly
sudo /usr/sbin/groupadd --force --gid 9703 lndinvoices
sudo /usr/sbin/groupadd --force --gid 9704 lndchainnotifier
sudo /usr/sbin/groupadd --force --gid 9705 lndsigner
sudo /usr/sbin/groupadd --force --gid 9706 lndwalletkit
sudo /usr/sbin/groupadd --force --gid 9707 lndrouter

echo ""
echo "*** Python DEFAULT libs & dependencies ***"

# for setup shell scripts
sudo apt -y install dialog bc python3-dialog

# libs (for global python scripts)
sudo -H python3 -m pip install grpcio==1.36.1
sudo -H python3 -m pip install googleapis-common-protos==1.53.0
sudo -H python3 -m pip install toml==0.10.1
sudo -H python3 -m pip install j2cli==0.3.10
sudo -H python3 -m pip install requests[socks]==2.21.0

echo ""
echo "*** SHELL SCRIPTS AND ASSETS ***"

# move files from gitclone
cd /home/admin/
sudo -u admin rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b ${githubBranch} https://github.com/${githubUser}/raspiblitz.git
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh

# install newest version of BlitzPy
blitzpy_wheel=$(ls -trR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E "*any.whl" | tail -n 1)
blitzpy_version=$(echo ${blitzpy_wheel} | grep -oE "([0-9]\.[0-9]\.[0-9])")
echo ""
echo "*** INSTALLING BlitzPy Version: ${blitzpy_version} ***"
sudo -H /usr/bin/python -m pip install "/home/admin/raspiblitz/home.admin/BlitzPy/dist/${blitzpy_wheel}" >/dev/null 2>&1 

# make sure lndlibs are patched for compatibility for both Python2 and Python3
if ! grep -Fxq "from __future__ import absolute_import" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
  sed -i -E '1 a from __future__ import absolute_import' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
fi
if ! grep -Eq "^from . import.*" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
  sed -i -E 's/^(import.*_pb2)/from . \1/' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
fi

# add /sbin to path for all
sudo bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

homeFile=/home/admin/.bashrc
autostart="automatically start main menu"
autostartDone=$(cat $homeFile|grep -c "$autostart")

if [ ${autostartDone} -eq 0 ]; then
  # bash autostart for admin
  sudo bash -c "echo '# shortcut commands' >> /home/admin/.bashrc"
  sudo bash -c "echo 'source /home/admin/_commands.sh' >> /home/admin/.bashrc"
  sudo bash -c "echo '# automatically start main menu for admin unless' >> /home/admin/.bashrc"
  sudo bash -c "echo '# when running in a tmux session' >> /home/admin/.bashrc"
  sudo bash -c "echo 'if [ -z \"\$TMUX\" ]; then' >> /home/admin/.bashrc"
  sudo bash -c "echo '    ./00raspiblitz.sh' >> /home/admin/.bashrc"
  sudo bash -c "echo 'fi' >> /home/admin/.bashrc"
  echo "autostart added to $homeFile"
else
  echo "autostart already in $homeFile"
fi

echo ""
echo "*** RASPIBLITZ EXTRAS ***"

# for background processes
sudo apt -y install screen

# for multiple (detachable/background) sessions when using SSH
# https://github.com/rootzoll/raspiblitz/issues/990
sudo apt -y install tmux

# optimization for torrent download
sudo bash -c "echo 'net.core.rmem_max = 4194304' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.core.wmem_max = 1048576' >> /etc/sysctl.conf"

# install a command-line fuzzy finder (https://github.com/junegunn/fzf)
sudo apt -y install fzf

sudo bash -c "echo '' >> /home/admin/.bashrc"
sudo bash -c "echo '# https://github.com/rootzoll/raspiblitz/issues/1784' >> /home/admin/.bashrc"
sudo bash -c "echo 'NG_CLI_ANALYTICS=ci' >> /home/admin/.bashrc"

sudo bash -c "echo '' >> /home/admin/.bashrc"
sudo bash -c "echo '# Raspiblitz' >> /home/admin/.bashrc"

homeFile=/home/admin/.bashrc
keyBindings="source /usr/share/doc/fzf/examples/key-bindings.bash"
keyBindingsDone=$(cat $homeFile|grep -c "$keyBindings")

if [ ${keyBindingsDone} -eq 0 ]; then
  sudo bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"
  echo "key-bindings added to $homeFile"
else
  echo "key-bindings already in $homeFile"
fi

echo ""
echo "*** SWAP FILE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#moving-the-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo ""
echo "*** INCREASE OPEN FILE LIMIT ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#increase-your-open-files-limit

sudo sed --in-place -i "56s/.*/*    soft nofile 128000/" /etc/security/limits.conf
sudo bash -c "echo '*    hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root soft nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo '# End of file' >> /etc/security/limits.conf"

sudo sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session

sudo sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
sudo bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"


# *** fail2ban ***
# based on https://stadicus.github.io/RaspiBolt/raspibolt_21_security.html
echo "*** HARDENING ***"
sudo apt install -y --no-install-recommends python3-systemd fail2ban 

# *** CACHE DISK IN RAM ***
echo "Activating CACHE RAM DISK ... "
sudo /home/admin/config.scripts/blitz.cache.sh on

# *** Wifi & Bluetooth ***
if [ "${baseImage}" = "raspbian" ]||[ "${baseImage}" = "raspios_arm64"  ]||\
   [ "${baseImage}" = "debian_rpi64" ]; then
   
  if [ "${modeWifi}" == "false" ]; then
    echo ""
    echo "*** DISABLE WIFI ***"
    sudo systemctl disable wpa_supplicant.service
    sudo ifconfig wlan0 down
  fi

  echo ""
  echo "*** DISABLE BLUETOOTH ***"

  configFile="/boot/config.txt"
  disableBT="dtoverlay=disable-bt"
  disableBTDone=$(cat $configFile|grep -c "$disableBT")

  if [ ${disableBTDone} -eq 0 ]; then
    # disable bluetooth module
    sudo echo "" >> $configFile
    sudo echo "# Raspiblitz" >> $configFile
    echo 'dtoverlay=pi3-disable-bt' | sudo tee -a $configFile
    echo 'dtoverlay=disable-bt' | sudo tee -a $configFile
  else
    echo "disable BT already in $configFile"
  fi

  # remove bluetooth services
  sudo systemctl disable bluetooth.service
  sudo systemctl disable hciuart.service

  # remove bluetooth packages
  sudo apt remove -y --purge pi-bluetooth bluez bluez-firmware
  
  echo
  echo "*** DISABLE AUDIO (snd_bcm2835) ***"
  sudo sed -i "s/^dtparam=audio=on/# dtparam=audio=on/g" /boot/config.txt
  echo
  
  echo "*** DISABLE DRM VC4 V3D driver ***"
  dtoverlay=vc4-fkms-v3d
  sudo sed -i "s/^dtoverlay=vc4-fkms-v3d/# dtoverlay=vc4-fkms-v3d/g" /boot/config.txt

fi

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if [ "${fatpack}" == "true" ]; then
  echo "*** FATPACK ***"
  echo "* Adding GO Framework ..."
  sudo /home/admin/config.scripts/bonus.go.sh on
  if [ "$?" != "0" ]; then
    echo "FATPACK FAILED"
    exit 1
  fi
  echo "* Adding nodeJS Framework ..."
  sudo /home/admin/config.scripts/bonus.nodejs.sh on
  if [ "$?" != "0" ]; then
    echo "FATPACK FAILED"
    exit 1
  fi
  echo "* Optional Packages (may be needed for extended features)"
  sudo apt-get install -y qrencode
  sudo apt-get install -y btrfs-tools
  sudo apt-get install -y secure-delete
  sudo apt-get install -y fbi
  sudo apt-get install -y ssmtp
  sudo apt-get install -y unclutter xterm python3-pyqt5
  sudo apt-get install -y xfonts-terminus
  sudo apt-get install -y nginx apache2-utils
  sudo apt-get install -y nginx
  sudo apt-get install -y python3-jinja2
  sudo apt-get install -y socat
  sudo apt-get install -y libatlas-base-dev
  sudo apt-get install -y mariadb-server mariadb-client
  sudo apt-get install -y hexyl
  sudo apt-get install -y autossh

else
  echo "* skipping FATPACK"
fi

# *** BOOTSTRAP ***
echo ""
echo "*** RASPI BOOTSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND ***
echo ""
echo "*** RASPI BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp /home/admin/assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

# "*** BITCOIN ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md#installation

echo ""
echo "*** PREPARING BITCOIN ***"

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="0.21.0"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# prepare directories
sudo rm -rf /home/admin/download
sudo -u admin mkdir /home/admin/download
cd /home/admin/download

# download, check and import signer key
sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
if [ ! -f "./laanwj-releases.asc" ]
then
  echo "!!! FAIL !!! Download laanwj-releases.asc not success."
  exit 1
fi
gpg --import --import-options show-only ./laanwj-releases.asc
fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep "${laanwjPGP}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> Bitcoin PGP author not as expected"
  echo "Should contain laanwjPGP: ${laanwjPGP}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./laanwj-releases.asc

# download signed binary sha256 hash sum file and check
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> BITCOIN MANIFEST IS CORRECT"
  echo "****************************************"
  echo ""
fi

# get the sha256 value for the corresponding platform from signed hash sum file
if [ ${isARM} -eq 1 ] ; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ ${isAARCH64} -eq 1 ] ; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ ${isX86_64} -eq 1 ] ; then
  bitcoinOSversion="x86_64-linux-gnu"
fi
bitcoinSHA256=$(grep -i "$bitcoinOSversion" SHA256SUMS.asc | cut -d " " -f1)

echo ""
echo "*** BITCOIN v${bitcoinVersion} for ${bitcoinOSversion} ***"

# download resources
binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
if [ ! -f "./${binaryName}" ]; then
   sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
fi
if [ ! -f "./${binaryName}" ]; then
   echo "!!! FAIL !!! Download BITCOIN BINARY not success."
   exit 1
else
  # check binary checksum test
  echo "- checksum test"
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  echo "Valid SHA256 checksum should be: ${bitcoinSHA256}"
  echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
  if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
    echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
    rm -v ./${binaryName}
    exit 1
  else
    echo ""
    echo "****************************************"
    echo "OK --> VERIFIED BITCOIN CHECKSUM CORRECT"
    echo "****************************************"
    sleep 10
    echo ""
  fi
fi

# install
sudo -u admin tar -xvf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
sleep 3
installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
if [ ${installed} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
  exit 1
fi
echo "- Bitcoin install OK"

echo ""
echo "*** PREPARING LIGHTNING ***"

# "*** LND ***"
## based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_40_lnd.md#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
lndVersion="0.12.1-beta"

# olaoluwa
#PGPauthor="roasbeef"
#PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
#PGPcheck="9769140D255C759B1EB77B46A96387A57CAAE94D"
# bitconner
PGPauthor="bitconner"
PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"
# Joost Jager
#PGPauthor="joostjager"
#PGPpkeys="https://keybase.io/joostjager/pgp_keys.asc"
#PGPcheck="D146D0F68939436268FA9A130E26BB61B76C4D3A"

# get LND resources
cd /home/admin/download

# download lnd binary checksum manifest
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt

# check if checksums are signed by lnd dev team
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-${PGPauthor}-v${lndVersion}.sig
sudo -u admin wget --no-check-certificate -N -O "pgp_keys.asc" ${PGPpkeys}
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(sudo gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> LND PGP author not as expected"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc
sleep 3
verifyResult=$(gpg --verify manifest-${PGPauthor}-v${lndVersion}.sig manifest-v${lndVersion}.txt 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> SIGNATURE LND MANIFEST IS CORRECT"
  echo "****************************************"
  echo ""
fi

# get the lndSHA256 for the corresponding platform from manifest file
if [ ${isARM} -eq 1 ] ; then
  lndOSversion="armv7"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isAARCH64} -eq 1 ] ; then
  lndOSversion="arm64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isX86_64} -eq 1 ] ; then
  lndOSversion="amd64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi

echo ""
echo "*** LND v${lndVersion} for ${lndOSversion} ***"
echo "SHA256 hash: $lndSHA256"
echo ""

# get LND binary
binaryName="lnd-linux-${lndOSversion}-v${lndVersion}.tar.gz"
if [ ! -f "./${binaryName}" ]; then
  lndDownloadUrl="https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}"
  echo "- downloading lnd binary --> ${lndDownloadUrl}"
  sudo -u admin wget ${lndDownloadUrl}
  echo "- download done"
else
  echo "- using existing lnd binary"
fi

# check binary was not manipulated (checksum test)
echo "- checksum test"
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
echo "Valid SHA256 checksum(s) should be: ${lndSHA256}"
echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
checksumCorrect=$(echo "${lndSHA256}" | grep -c "${binaryChecksum}")
if [ "${checksumCorrect}" != "1" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum in manifest: ${lndSHA256}"
  rm -v ./${binaryName}
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> VERIFIED LND CHECKSUM IS CORRECT"
  echo "****************************************"
  echo ""
  sleep 10
fi

# install
echo "- install LND binary"
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi
correctVersion=$(sudo -u admin lnd --version | grep -c "${lndVersion}")
if [ ${correctVersion} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> installed LND is not version ${lndVersion}"
  sudo -u admin lnd --version
  exit 1
fi
sudo chown -R admin /home/admin
echo "- OK install of LND done"

echo ""
echo "*** DISPLAY OPTIONS ***"
# (do last - because makes a reboot)
# based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
if [ "${lcdInstalled}" != "false" ]; then

  # lcd preparations based on os
  if [ "${baseImage}" = "raspbian" ]||[ "${baseImage}" = "raspios_arm64" ]||\
     [ "${baseImage}" = "debian_rpi64" ]||[ "${baseImage}" = "armbian" ]||\
     [ "${baseImage}" = "ubuntu" ]; then
    homeFile=/home/pi/.bashrc
    autostart="automatic start the LCD"
    autostartDone=$(cat $homeFile|grep -c "$autostart")
    if [ ${autostartDone} -eq 0 ]; then
      # bash autostart for pi
      # run as exec to dont allow easy physical access by keyboard
      # see https://github.com/rootzoll/raspiblitz/issues/54
      sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
      sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/pi/.bashrc'
      sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
      sudo bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'
      echo "autostart LCD added to $homeFile"
    else
      echo "autostart LCD already in $homeFile"
    fi
  fi
  if [ "${baseImage}" = "dietpi" ]; then
    homeFile=/home/dietpi/.bashrc
    startLCD="automatic start the LCD"
    autostartDone=$(cat $homeFile|grep -c "$startLCD")
    if [ ${autostartDone} -eq 0 ]; then
      # bash autostart for dietpi
      sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/dietpi/.bashrc'
      sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/dietpi/.bashrc'
      sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/dietpi/.bashrc'
      sudo bash -c 'echo "exec \$SCRIPT" >> /home/dietpi/.bashrc'
      echo "autostart LCD added to $homeFile"
    else
      echo "autostart LCD already in $homeFile"
    fi
  fi

  echo ""
  if [ "${lcdInstalled}" == "GPIO" ]; then
    if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "dietpi" ]; then
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
 
      if [ "${baseImage}" = "dietpi" ]; then
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
    elif [ "${baseImage}" = "raspios_arm64"  ] || [ "${baseImage}" = "debian_rpi64" ]; then
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
      rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
      mkdir -p /etc/X11/xorg.conf.d
      cp -rf ./99-calibration.conf  /etc/X11/xorg.conf.d/99-calibration.conf
      # cp -rf ./99-fbturbo.conf  /etc/X11/xorg.conf.d/99-fbturbo.conf # there is no such file

      # load module on boot
      cp ./waveshare35a.dtbo /boot/overlays/
      echo "hdmi_force_hotplug=1" >> /boot/config.txt 
      # don't enable I2C, SPI and UART ports by default
      # echo "dtparam=i2c_arm=on" >> /boot/config.txt
      # echo "dtparam=spi=on" >> /boot/config.txt
      # echo "enable_uart=1" >> /boot/config.txt
      echo "dtoverlay=waveshare35a:rotate=90" >> /boot/config.txt
      cp ./cmdline.txt /boot/

      # touch screen calibration
      apt-get install -y xserver-xorg-input-evdev
      cp -rf /usr/share/X11/xorg.conf.d/10-evdev.conf /usr/share/X11/xorg.conf.d/45-evdev.conf
      # TODO manual touchscreen calibration option
      # https://github.com/tux1c/wavesharelcd-64bit-rpi#adapting-guide-to-other-lcds
    fi
  else
    echo "FAIL: Unknown LCD-DRIVER: ${lcdInstalled}"
    exit 1
  fi

else
  echo "- LCD options are deactivated"
fi

# *** RASPIBLITZ IMAGE READY ***
echo ""
echo "**********************************************"
echo "SD CARD BUILD DONE"
echo "**********************************************"
echo ""

if [ "${lcdInstalled}" != "false" ]; then
  echo "Your SD Card Image for RaspiBlitz is almost ready."
  if [ "${baseImage}" = "raspbian" ]; then
    echo "Last step is to install LCD drivers. This will reboot your Pi when done."
    echo ""
  fi
else
  echo "Your SD Card Image for RaspiBlitz is ready."
fi
echo "Take the chance & look thru the output above if you can spot any error."
echo ""
if [ "${lcdInstalled}" != "false" ]; then
  echo "After final reboot - your SD Card Image is ready."
  echo ""
fi
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "login once after reboot without external HDD/SSD and run 'XXprepareRelease.sh'"
echo "REMEMBER for login now use --> user:admin password:raspiblitz"
echo ""

if [ "${lcdInstalled}" == "GPIO" ]; then
  # activate LCD and trigger reboot
  # dont do this on dietpi to allow for automatic build
  if [ "${baseImage}" = "raspbian" ]; then
    sudo chmod +x -R /home/admin/LCD-show
    cd /home/admin/LCD-show/
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./LCD35-show
  elif [ "${baseImage}" = "raspios_arm64" ] || [ "${baseImage}" = "debian_rpi64" ]; then
    sudo chmod +x -R /home/admin/wavesharelcd-64bit-rpi
    cd /home/admin/wavesharelcd-64bit-rpi
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./install.sh
  else
    echo "Use 'sudo reboot' to restart manually."
  fi
fi