#!/bin/bash
#########################################################################
# Build your SD card image based on:
# 2021-10-30-raspios-bullseye-arm64.zip
# https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2021-11-08/
# SHA256: b35425de5b4c5b08959aa9f29b9c0f730cd0819fe157c3e37c56a6d0c5c13ed8
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script:
##########################################################################

defaultBranchVersion="v1.7"

echo
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP ${defaultBranchVersion}.1 *"
echo "*****************************************"
echo "For details on optional parameters - see build script source code:"

# 1st optional parameter: NO-INTERACTION
# ----------------------------------------
# When 'true' then no questions will be asked on building .. so it can be used in build scripts
# for containers or as part of other build scripts (default is false)

noInteraction="$1"
if [ ${#noInteraction} -eq 0 ]; then
  noInteraction="false"
fi
if [ "${noInteraction}" != "true" ] && [ "${noInteraction}" != "false" ]; then
  echo "ERROR: NO-INTERACTION parameter needs to be either 'true' or 'false'"
  exit 1
else
  echo "1) will use NO-INTERACTION --> '${noInteraction}'"
fi

# 2nd optional parameter: FATPACK
# -------------------------------
# could be 'true' or 'false' (default)
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...

fatpack="$2"
if [ ${#fatpack} -eq 0 ]; then
  fatpack="false"
fi
if [ "${fatpack}" != "true" ] && [ "${fatpack}" != "false" ]; then
  echo "ERROR: FATPACK parameter needs to be either 'true' or 'false'"
  exit 1
else
  echo "2) will use FATPACK --> '${fatpack}'"
fi

# 3rd optional parameter: GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblitz repo - 'rootzoll' is default
# The 'raspiblitz' repo of this user is used to provisioning sd card 
# with raspiblitz assets/scripts later on.
# If this parameter is set also the branch needs to be given (see next parameter).
githubUser="$3"
if [ ${#githubUser} -eq 0 ]; then
  githubUser="rootzoll"
fi
echo "3) will use GITHUB-USERNAME --> '${githubUser}'"

# 4th optional parameter: GITHUB-BRANCH
# -------------------------------------
# could be any valid branch of the given GITHUB-USERNAME forked raspiblitz repo - take ${defaultBranchVersion} is default
githubBranch="$4"
if [ ${#githubBranch} -eq 0 ]; then
  githubBranch="${defaultBranchVersion}"
fi
echo "4) will use GITHUB-BRANCH --> '${githubBranch}'"

# 5th optional parameter: DISPLAY-CLASS
# ----------------------------------------
# Could be 'hdmi', 'headless' or 'lcd' (lcd is default)
# On 'false' the standard video output is used (HDMI) by default.
# https://github.com/rootzoll/raspiblitz/issues/1265#issuecomment-813369284
displayClass="$5"
if [ ${#displayClass} -eq 0 ]; then
  displayClass="lcd"
fi
if [ "${displayClass}" == "false" ]; then
  displayClass="hdmi"
fi
if [ "${displayClass}" != "hdmi" ] && [ "${displayClass}" != "lcd" ] && [ "${displayClass}" != "headless" ]; then
  echo "ERROR: DISPLAY-CLASS parameter needs to be 'lcd', 'hdmi' or 'headless'"
  exit 1
else
  echo "5) will use DISPLAY-CLASS --> '${displayClass}'"
fi

# 6th optional parameter: TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
tweakBootdrives="$6"
if [ ${#tweakBootdrives} -eq 0 ]; then
  tweakBootdrives="true"
fi
if [ "${tweakBootdrives}" != "true" ] && [ "${tweakBootdrives}" != "false" ]; then
  echo "ERROR: TWEAK-BOOTDRIVE parameter needs to be either 'true' or 'false'"
  exit 1
else
  echo "6) will use TWEAK-BOOTDRIVE --> '${tweakBootdrives}'"
fi

# 7th optional parameter: WIFI
# ---------------------------------------
# could be 'false' or 'true' (default) or a valid WIFI country code like 'US' (default)
# If 'false' WIFI will be deactivated by default
# If 'true' WIFI will be activated by with default country code 'US'
# If any valid wifi country code Wifi will be activated with that country code by default
modeWifi="$7"
if [ ${#modeWifi} -eq 0 ] || [ "${modeWifi}" == "true" ]; then
  modeWifi="US"
fi
echo "7) will use WIFI --> '${modeWifi}'"

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
cpu="?"
if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
  cpu="arm"
elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
  cpu="aarch64"
elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
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
# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
baseimage="?"
if [ $(grep -c 'Raspbian' /etc/os-release 2>/dev/null) -gt 0 ]; then
  baseimage="raspbian"
elif [ $(grep -c 'Debian' /etc/os-release 2>/dev/null) -gt 0 ]; then
  if [ $(uname -n | grep -c 'rpi') -gt 0 ] && [ "${cpu}" = aarch64 ]; then
    baseimage="debian_rpi64"
  elif [ $(uname -n | grep -c 'raspberrypi') -gt 0 ] && [ "${cpu}" = aarch64 ]; then
    baseimage="raspios_arm64"
  elif [ "${cpu}" = "arm" ] || [ "${cpu}" = "aarch64" ]  ; then
    baseimage="armbian"
  else
    baseimage="debian"
  fi
elif [ $(grep -c 'Ubuntu' /etc/os-release 2>/dev/null) -gt 0 ]; then
  baseimage="ubuntu"
elif [ $(uname -n | grep -c 'DietPi') -gt 0 ]; then
  baseimage="dietpi"
elif [ "${baseimage}" = "?" ]; then
  cat /etc/os-release 2>/dev/null
  echo "!!! FAIL: Base Image cannot be detected or is not supported."
  exit 1
fi
echo "X) will use OPERATINGSYSTEM ---> '${baseimage}'"

# USER-CONFIRMATION
if [ "${noInteraction}" != "true" ]; then
  echo -n "Do you agree with all parameters above? (yes/no) "
  read installRaspiblitzAnswer
  if [ "$installRaspiblitzAnswer" != "yes" ] ; then
    exit 1
  fi
fi
echo "Building RaspiBlitz ..."
echo
sleep 3

# INSTALL TOR
echo "*** INSTALL TOR BY DEFAULT ***"
echo
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
torSourceListAvailable=$(sudo grep -c 'https://deb.torproject.org/torproject.org' /etc/apt/sources.list)
echo "torSourceListAvailable=${torSourceListAvailable}"  
if [ ${torSourceListAvailable} -eq 0 ]; then
  echo "- adding TOR sources ..."
  if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ] || [ "${baseimage}" = "armbian" ] || [ "${baseimage}" = "dietpi" ] || [ "${baseimage}" = "debian" ]; then
    echo "- using https://deb.torproject.org/torproject.org bullseye"
    echo "deb https://deb.torproject.org/torproject.org bullseye main" | sudo tee -a /etc/apt/sources.list
    echo "deb-src https://deb.torproject.org/torproject.org bullseye main" | sudo tee -a /etc/apt/sources.list
  elif [ "${baseimage}" = "ubuntu" ]; then
    echo "- using https://deb.torproject.org/torproject.org focal"
    echo "deb https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list
    echo "deb-src https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list    
  else
    echo "!!! FAIL: No Tor sources for os: ${baseimage}"
    exit 1
  fi
  echo "- OK sources added"
else
  echo "Tor sources are available"
fi

echo "*** Install & Enable Tor ***"
sudo apt update -y
sudo apt install tor tor-arm torsocks -y
echo

# FIXING LOCALES
# https://github.com/rootzoll/raspiblitz/issues/138
# https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
# https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "dietpi" ] || \
   [ "${baseimage}" = "raspios_arm64" ]||[ "${baseimage}" = "debian_rpi64" ]; then
  echo
  echo "*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=en_US.UTF-8
  export LANG=en_US.UTF-8
  if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "dietpi" ]; then
    export LC_ALL=en_US.UTF-8

    # https://github.com/rootzoll/raspiblitz/issues/684
    sudo sed -i "s/^    SendEnv LANG LC.*/#   SendEnv LANG LC_*/g" /etc/ssh/ssh_config

    # remove unnecessary files
    sudo rm -rf /home/pi/MagPi
    # https://www.reddit.com/r/linux/comments/lbu0t1/microsoft_repo_installed_on_all_raspberry_pis/
    sudo rm -f /etc/apt/sources.list.d/vscode.list 
    sudo rm -f /etc/apt/trusted.gpg.d/microsoft.gpg
  fi
  if [ ! -f /etc/apt/sources.list.d/raspi.list ]; then
    echo "# Add the archive.raspberrypi.org/debian/ to the sources.list"
    echo "deb http://archive.raspberrypi.org/debian/ bullseye main" | sudo tee /etc/apt/sources.list.d/raspi.list
  fi
fi

echo "*** Remove not needed packages ***"
sudo apt remove -y --purge libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi minecraft-pi plymouth python2 vlc
sudo apt clean
sudo apt -y autoremove

echo
echo "*** Python DEFAULT libs & dependencies ***"

if [ -f "/usr/bin/python3.8" ]; then
  # make sure /usr/bin/python exists (and calls Python3.7 in bullseye)
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  echo "python calls python3.8"
elif [ -f "/usr/bin/python3.9" ]; then
  # use python 3.9 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  sudo ln -s /usr/bin/python3.9 /usr/bin/python3.8
  echo "python calls python3.9"
else
  echo "!!! FAIL !!!"
  echo "There is no tested version of python present"
  exit 1
fi

# for setup shell scripts
sudo apt -y install dialog bc python3-dialog

# libs (for global python scripts)
sudo -H python3 -m pip install --upgrade pip
sudo -H python3 -m pip install grpcio==1.38.1
sudo -H python3 -m pip install googleapis-common-protos==1.53.0
sudo -H python3 -m pip install toml==0.10.1
sudo -H python3 -m pip install j2cli==0.3.10
sudo -H python3 -m pip install requests[socks]==2.21.0

echo
echo "*** UPDATE Debian***"
sudo apt update -y
sudo apt upgrade -f -y

echo
echo "*** PREPARE ${baseimage} ***"

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
if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64" ]||\
   [ "${baseimage}" = "debian_rpi64" ]; then

  echo
  echo "*** PREPARE RASPBIAN ***"
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
  max_usb_currentDone=$(grep -c "$max_usb_current" $configFile)

  if [ ${max_usb_currentDone} -eq 0 ]; then
    echo | sudo tee -a $configFile
    echo "# Raspiblitz" | sudo tee -a $configFile
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
  fsOption1InFile=$(grep -c ${fsOption1} ${kernelOptionsFile})
  fsOption2InFile=$(grep -c ${fsOption2} ${kernelOptionsFile})

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
if [ $(uname -a | grep -c 'tegra') -gt 0 ] ; then
  echo "Nvidia --> disable GUI on boot"
  sudo systemctl set-default multi-user.target
fi

echo
echo "*** CONFIG ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#raspi-config

# set new default password for root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

# prepare auto-start of 00infoLCD.sh script on pi user login (just kicks in if auto-login of pi is activated in HDMI or LCD mode)
if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64" ]||\
  [ "${baseimage}" = "debian_rpi64" ]||[ "${baseimage}" = "armbian" ]||\
  [ "${baseimage}" = "ubuntu" ]; then
  homeFile=/home/pi/.bashrc
  autostartDone=$(grep -c "automatic start the LCD" $homeFile)
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
elif [ "${baseimage}" = "dietpi" ]; then
  homeFile=/home/dietpi/.bashrc
  autostartDone=$(grep -c "automatic start the LCD" $homeFile)
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
else
  echo "WARN: Script Autostart not available for baseimage(${baseimage}) - may just run on 'headless'"
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
echo >> ./rsyslog
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
echo >> ./rsyslog
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
echo >> ./rsyslog
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

echo
echo "*** SOFTWARE UPDATE ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#software-update

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
if [ "${baseimage}" = "armbian" ]; then
  # add armbian config
  sudo apt install armbian-config -y
fi

# dependencies for python
sudo apt install -y python3-venv python3-dev python3-wheel python3-jinja2 python3-pip

# make sure /usr/bin/pip exists (and calls pip3 in Debian bullseye)
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
# make sure sqlite3 is available
sudo apt install -y sqlite3

sudo apt clean
sudo apt -y autoremove

echo
echo "*** ADDING MAIN USER admin ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#add-users
# using the default password 'raspiblitz'

sudo adduser --disabled-password --gecos "" admin --ingroup admin
echo "admin:raspiblitz" | sudo chpasswd
sudo adduser admin sudo
sudo chsh admin -s /bin/bash

# configure sudo for usage without password entry
echo '%sudo ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo

# WRITE BASIC raspiblitz.info to sdcard
# if further info gets added .. make sure to keep that on: blitz.preparerelease.sh
echo "baseimage=${baseimage}" > /home/admin/raspiblitz.info
echo "cpu=${cpu}" >> /home/admin/raspiblitz.info
echo "displayClass=headless" >> /home/admin/raspiblitz.info
sudo mv ./raspiblitz.info /home/admin/raspiblitz.info
sudo chmod 755 /home/admin/raspiblitz.info

echo
echo "*** ADDING SERVICE USER bitcoin"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#add-users

# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd
# make home directory readable
sudo chmod 755 /home/bitcoin

echo
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

echo
echo "*** SHELL SCRIPTS & ASSETS ***"

# copy raspiblitz repo from github
cd /home/admin/ || exit 1
sudo -u admin git config --global user.name "${githubUser}"
sudo -u admin git config --global user.email "johndoe@example.com"
sudo rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b ${githubBranch} https://github.com/${githubUser}/raspiblitz.git
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin chmod 755 *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod 755 /home/admin/config.scripts/*.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/setup.scripts /home/admin/
sudo -u admin chmod 755 /home/admin/setup.scripts/*.sh

# install newest version of BlitzPy
blitzpy_wheel=$(ls -tR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E "*any.whl" | tail -n 1)
blitzpy_version=$(echo ${blitzpy_wheel} | grep -oE "([0-9]\.[0-9]\.[0-9])")
echo
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

# replace boot splash image when raspbian
if [ "${baseimage}" == "raspbian" ]; then
  echo "* replacing boot splash"
  sudo cp /home/admin/raspiblitz/pictures/splash.png /usr/share/plymouth/themes/pix/splash.png
fi

echo
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

# raspiblitz custom command prompt #2400
if ! grep -Eq "^[[:space:]]*PS1.*₿" /home/admin/.bashrc; then
    sudo sed -i '/^unset color_prompt force_color_prompt$/i # raspiblitz custom command prompt https://github.com/rootzoll/raspiblitz/issues/2400' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i raspiIp=$(hostname -I | cut -d " " -f1)' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i if [ "$color_prompt" = yes ]; then' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\[\\033[00;33m\\]\\u@$raspiIp:\\[\\033[00;34m\\]\\w\\[\\033[01;35m\\]$(__git_ps1 "(%s)") \\[\\033[01;33m\\]₿\\[\\033[00m\\] \x27' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i else' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\u@$raspiIp:\\w₿ \x27' /home/admin/.bashrc
    sudo sed -i '/^unset color_prompt force_color_prompt$/i fi' /home/admin/.bashrc
fi

homeFile=/home/admin/.bashrc
keyBindings="source /usr/share/doc/fzf/examples/key-bindings.bash"
keyBindingsDone=$(grep -c "$keyBindings" $homeFile)

if [ ${keyBindingsDone} -eq 0 ]; then
  sudo bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"
  echo "key-bindings added to $homeFile"
else
  echo "key-bindings already in $homeFile"
fi

homeFile=/home/admin/.bashrc
autostart="automatically start main menu"
autostartDone=$(grep -c "$autostart" $homeFile)

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

sudo bash -c "echo '' >> /home/admin/.bashrc"
sudo bash -c "echo '# Raspiblitz' >> /home/admin/.bashrc"

echo
echo "*** SWAP FILE ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo
echo "*** INCREASE OPEN FILE LIMIT ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_21_security.html#increase-your-open-files-limit

sudo sed --in-place -i "56s/.*/*    soft nofile 128000/" /etc/security/limits.conf
sudo bash -c "echo '*    hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root soft nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo '# End of file' >> /etc/security/limits.conf"

sudo sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session

sudo sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
sudo bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"


# *** fail2ban ***
# based on https://raspibolt.github.io/raspibolt/raspibolt_21_security.html#fail2ban
echo "*** HARDENING ***"
sudo apt install -y --no-install-recommends python3-systemd fail2ban 

# *** CACHE DISK IN RAM ***
echo "Activating CACHE RAM DISK ... "
sudo /home/admin/config.scripts/blitz.cache.sh on

# *** Wifi, Bluetooth & other configs ***
if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64"  ]||\
   [ "${baseimage}" = "debian_rpi64" ]; then
   
  if [ "${modeWifi}" == "false" ]; then
    echo
    echo "*** DISABLE WIFI ***"
    sudo systemctl disable wpa_supplicant.service
    sudo ifconfig wlan0 down
  fi

  echo
  echo "*** DISABLE BLUETOOTH ***"

  configFile="/boot/config.txt"
  disableBT="dtoverlay=disable-bt"
  disableBTDone=$(grep -c "$disableBT" $configFile)

  if [ ${disableBTDone} -eq 0 ]; then
    # disable bluetooth module
    echo >> $configFile
    echo "# Raspiblitz" >> $configFile
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

  # disable audio
  echo "*** DISABLE AUDIO (snd_bcm2835) ***"
  sudo sed -i "s/^dtparam=audio=on/# dtparam=audio=on/g" /boot/config.txt
  echo
  
  # disable DRM VC4 V3D
  echo "*** DISABLE DRM VC4 V3D driver ***"
  dtoverlay=vc4-fkms-v3d
  sudo sed -i "s/^dtoverlay=vc4-fkms-v3d/# dtoverlay=vc4-fkms-v3d/g" /boot/config.txt
  echo

  # I2C fix (make sure dtparam=i2c_arm is not on)
  # see: https://github.com/rootzoll/raspiblitz/issues/1058#issuecomment-739517713
  sudo sed -i "s/^dtparam=i2c_arm=.*//g" /boot/config.txt 
fi

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if [ "${fatpack}" == "true" ]; then
  echo "*** FATPACK ***"
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

  # *** UPDATE FALLBACK NODE LIST (only as part of fatpack) *** see https://github.com/rootzoll/raspiblitz/issues/1888
  echo "*** FALLBACK NODE LIST ***"
  sudo -u admin curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o /home/admin/fallback.nodes
  byteSizeList=$(sudo -u admin stat -c %s /home/admin/fallback.nodes)
  if [ ${#byteSizeList} -eq 0 ] || [ ${byteSizeList} -lt 10240 ]; then 
    echo "WARN: Failed downloading fresh FALLBACK NODE LIST --> https://bitnodes.io/api/v1/snapshots/latest/"
    sudo rm /home/admin/fallback.nodes 2>/dev/null
    sudo cp /home/admin/assets/fallback.nodes /home/admin/fallback.nodes
  fi
  sudo chown admin:admin /home/admin/fallback.nodes

else
  echo "* skipping FATPACK"
fi

# *** BOOTSTRAP ***
echo
echo "*** RASPI BOOTSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND ***
echo
echo "*** RASPI BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp /home/admin/assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

###########
# BITCOIN #
###########
echo
/home/admin/config.scripts/bitcoin.install.sh install || exit 1

#######
# LND #
#######
echo
/home/admin/config.scripts/lnd.install.sh install || exit 1

###############
# C-LIGHTNING #
###############
echo
/home/admin/config.scripts/cl.install.sh install || exit 1

echo
echo "*** raspiblitz.info ***"
sudo cat /home/admin/raspiblitz.info

# *** RASPIBLITZ IMAGE READY INFO ***
echo
echo "**********************************************"
echo "BASIC SD CARD BUILD DONE"
echo "**********************************************"
echo
echo "Your SD Card Image for RaspiBlitz is ready (might still do display config)."
echo "Take the chance & look thru the output above if you can spot any errors or warnings."
echo
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "1. login fresh --> user:admin password:raspiblitz"
echo "2. run --> release"
echo

# (do last - because might trigger reboot)
if [ "${displayClass}" != "headless" ] || [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blitz.display.sh set-display ${displayClass}"
  sudo /home/admin/config.scripts/blitz.display.sh set-display ${displayClass}
  sudo /home/admin/config.scripts/blitz.display.sh rotate 1
fi

echo "# BUILD DONE - see above"

# optimization for torrent download
sudo bash -c "echo 'net.core.rmem_max = 4194304' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.core.wmem_max = 1048576' >> /etc/sysctl.conf"

# install a command-line fuzzy finder (https://github.com/junegunn/fzf)
sudo apt -y install fzf

sudo bash -c "echo '' >> /home/admin/.bashrc"
sudo bash -c "echo '# https://github.com/rootzoll/raspiblitz/issues/1784' >> /home/admin/.bashrc"
sudo bash -c "echo 'NG_CLI_ANALYTICS=ci' >> /home/admin/.bashrc"

homeFile=/home/admin/.bashrc
keyBindings="source /usr/share/doc/fzf/examples/key-bindings.bash"
keyBindingsDone=$(grep -c "$keyBindings" $homeFile)

if [ ${keyBindingsDone} -eq 0 ]; then
  sudo bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"
  echo "key-bindings added to $homeFile"
else
  echo "key-bindings already in $homeFile"
fi

homeFile=/home/admin/.bashrc
autostart="automatically start main menu"
autostartDone=$(grep -c "$autostart" $homeFile)

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

sudo bash -c "echo '' >> /home/admin/.bashrc"
sudo bash -c "echo '# Raspiblitz' >> /home/admin/.bashrc"

echo
echo "*** SWAP FILE ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo
echo "*** INCREASE OPEN FILE LIMIT ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_21_security.html#increase-your-open-files-limit

sudo sed --in-place -i "56s/.*/*    soft nofile 128000/" /etc/security/limits.conf
sudo bash -c "echo '*    hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root soft nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo '# End of file' >> /etc/security/limits.conf"

sudo sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session

sudo sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
sudo bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"


# *** fail2ban ***
# based on https://raspibolt.github.io/raspibolt/raspibolt_21_security.html#fail2ban
echo "*** HARDENING ***"
sudo apt install -y --no-install-recommends python3-systemd fail2ban 

# *** CACHE DISK IN RAM ***
echo "Activating CACHE RAM DISK ... "
sudo /home/admin/config.scripts/blitz.cache.sh on

# *** Wifi, Bluetooth & other configs ***
if [ "${baseimage}" = "raspbian" ]||[ "${baseimage}" = "raspios_arm64"  ]||\
   [ "${baseimage}" = "debian_rpi64" ]; then
   
  if [ "${modeWifi}" == "false" ]; then
    echo
    echo "*** DISABLE WIFI ***"
    sudo systemctl disable wpa_supplicant.service
    sudo ifconfig wlan0 down
  fi

  echo
  echo "*** DISABLE BLUETOOTH ***"

  configFile="/boot/config.txt"
  disableBT="dtoverlay=disable-bt"
  disableBTDone=$(grep -c "$disableBT" $configFile)

  if [ ${disableBTDone} -eq 0 ]; then
    # disable bluetooth module
    echo >> $configFile
    echo "# Raspiblitz" >> $configFile
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

  # disable audio
  echo "*** DISABLE AUDIO (snd_bcm2835) ***"
  sudo sed -i "s/^dtparam=audio=on/# dtparam=audio=on/g" /boot/config.txt
  echo
  
  # disable DRM VC4 V3D
  echo "*** DISABLE DRM VC4 V3D driver ***"
  dtoverlay=vc4-fkms-v3d
  sudo sed -i "s/^dtoverlay=vc4-fkms-v3d/# dtoverlay=vc4-fkms-v3d/g" /boot/config.txt
  echo

  # I2C fix (make sure dtparam=i2c_arm is not on)
  # see: https://github.com/rootzoll/raspiblitz/issues/1058#issuecomment-739517713
  sudo sed -i "s/^dtparam=i2c_arm=.*//g" /boot/config.txt 
fi

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if [ "${fatpack}" == "true" ]; then
  echo "*** FATPACK ***"
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

  # *** UPDATE FALLBACK NODE LIST (only as part of fatpack) *** see https://github.com/rootzoll/raspiblitz/issues/1888
  echo "*** FALLBACK NODE LIST ***"
  sudo -u admin curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o /home/admin/fallback.nodes
  byteSizeList=$(sudo -u admin stat -c %s /home/admin/fallback.nodes)
  if [ ${#byteSizeList} -eq 0 ] || [ ${byteSizeList} -lt 10240 ]; then 
    echo "WARN: Failed downloading fresh FALLBACK NODE LIST --> https://bitnodes.io/api/v1/snapshots/latest/"
    sudo rm /home/admin/fallback.nodes 2>/dev/null
    sudo cp /home/admin/assets/fallback.nodes /home/admin/fallback.nodes
  fi
  sudo chown admin:admin /home/admin/fallback.nodes

else
  echo "* skipping FATPACK"
fi

# *** BOOTSTRAP ***
echo
echo "*** RASPI BOOTSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND ***
echo
echo "*** RASPI BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp /home/admin/assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

###########
# BITCOIN #
###########
echo
/home/admin/config.scripts/bitcoin.install.sh install || exit 1

#######
# LND #
#######
echo
/home/admin/config.scripts/lnd.install.sh install || exit 1

###############
# C-LIGHTNING #
###############
echo
/home/admin/config.scripts/cl.install.sh install || exit 1

echo
echo "*** raspiblitz.info ***"
sudo cat /home/admin/raspiblitz.info

# *** RASPIBLITZ IMAGE READY INFO ***
echo
echo "**********************************************"
echo "BASIC SD CARD BUILD DONE"
echo "**********************************************"
echo
echo "Your SD Card Image for RaspiBlitz is ready (might still do display config)."
echo "Take the chance & look thru the output above if you can spot any errors or warnings."
echo
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "1. login fresh --> user:admin password:raspiblitz"
echo "2. run --> release"
echo

# (do last - because might trigger reboot)
if [ "${displayClass}" != "headless" ] || [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blitz.display.sh set-display ${displayClass}"
  sudo /home/admin/config.scripts/blitz.display.sh set-display ${displayClass}
  sudo /home/admin/config.scripts/blitz.display.sh rotate 1
fi

echo "# BUILD DONE - see above"
