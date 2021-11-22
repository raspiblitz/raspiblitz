#!/usr/bin/env bash
#########################################################################
# Build your SD card image based on: 2021-10-30-raspios-bullseye-arm64
# https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2021-11-08/
# SHA256: b35425de5b4c5b08959aa9f29b9c0f730cd0819fe157c3e37c56a6d0c5c13ed8
# PGP fingerprint: 8738CD6B956F460C
# PGP key: https://www.raspberrypi.org/raspberrypi_downloads.gpg.key
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script:
##########################################################################

# https://github.com/rootzoll/raspiblitz/tags
defaultTag="v1.7.1"
echo
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP ${defaultTag} *"
echo "*****************************************"
echo "For details on optional parameters - see build script source code:"

# 1st optional parameter: NO-INTERACTION
# ----------------------------------------
# When 'true' then no questions will be asked on building .. so it can be used in build scripts
# for containers or as part of other build scripts (default is false)
noInteraction="${1:-false}"
if [ "${noInteraction}" != "true" ] && [ "${noInteraction}" != "false" ]; then
  echo "ERROR: NO-INTERACTION parameter needs to be either 'true' or 'false'"
  exit 1
fi
echo "1) NO-INTERACTION --> '${noInteraction}'"

# 2nd optional parameter: FATPACK
# -------------------------------
# could be 'true' or 'false' (default)
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...
fatpack="${2:-false}"
if [ "${fatpack}" != "true" ] && [ "${fatpack}" != "false" ]; then
  echo "ERROR: FATPACK parameter needs to be either 'true' or 'false'"
  exit 1
fi
echo "2) FATPACK --> '${fatpack}'"

# 3rd optional parameter: GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblitz repo - 'rootzoll' is default
# The 'raspiblitz' repo of this user is used to provisioning sd card
# with raspiblitz assets/scripts later on.
# If this parameter is set also the branch needs to be given (see next parameter).
githubUser="${3:-rootzoll}"
echo "3) GITHUB-USERNAME --> '${githubUser}'"

# 4th optional parameter: GITHUB-BRANCH
# -------------------------------------
# could be any valid branch of the given GITHUB-USERNAME forked raspiblitz repo - take ${defaultTag} is default
githubBranch="${4:-"${defaultTag}"}"
echo "4) GITHUB-BRANCH --> '${githubBranch}'"

# 5th optional parameter: DISPLAY-CLASS
# ----------------------------------------
# Could be 'hdmi', 'headless' or 'lcd' (lcd is default)
# On 'false' the standard video output is used (HDMI) by default.
# https://github.com/rootzoll/raspiblitz/issues/1265#issuecomment-813369284
displayClass="${5:-lcd}"
[ "${displayClass}" = "false" ] && displayClass="hdmi"
if [ "${displayClass}" != "hdmi" ] && [ "${displayClass}" != "lcd" ] && [ "${displayClass}" != "headless" ]; then
  echo "ERROR: DISPLAY-CLASS parameter needs to be 'lcd', 'hdmi' or 'headless'"
  exit 1
fi
echo "5) DISPLAY-CLASS --> '${displayClass}'"

# 6th optional parameter: TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
tweakBootdrives="${6:-true}"
if [ "${tweakBootdrives}" != "true" ] && [ "${tweakBootdrives}" != "false" ]; then
  echo "ERROR: TWEAK-BOOTDRIVE parameter needs to be either 'true' or 'false'"
  exit 1
fi
echo "6) TWEAK-BOOTDRIVE --> '${tweakBootdrives}'"

# 7th optional parameter: WIFI
# ---------------------------------------
# could be 'false' or 'true' (default) or a valid WIFI country code like 'US' (default)
# If 'false' WIFI will be deactivated by default
# If 'true' WIFI will be activated by with default country code 'US'
# If any valid wifi country code Wifi will be activated with that country code by default
modeWifi="${7:-US}"
[ "${modeWifi}" = "true" ] && modeWifi="US"
echo "7) WIFI --> '${modeWifi}'"

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
cpu="$(uname -m)"
architecture="$(dpkg --print-architecture)"
if [ "${cpu}" != "arm" ] && [ "${cpu}" != "aarch64" ] && [ "${cpu}" != "x86_64" ]; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 not on:"
  ${cpu}
  exit 1
fi
echo "8) CPU-ARCHITECTURE --> '${cpu}'"

# AUTO-DETECTION: OPERATINGSYSTEM
# ---------------------------------------
baseimage="$(lsb_release -si 2>/dev/null)"
if [ "${baseimage}" = "Debian" ]; then
  if [ "$(uname -n | grep -c 'rpi')" -gt 0 ] && [ "${cpu}" = "aarch64" ]; then
    baseimage="debian_rpi64"
  elif [ "$(uname -n | grep -c 'raspberrypi')" -gt 0 ] && [ "${cpu}" = "aarch64" ]; then
    baseimage="raspios_arm64"
  elif [ "${cpu}" = "aarch64" ] || [ "${cpu}" = "arm" ] ; then
    baseimage="armbian"
  fi
elif [ "${baseimage}" = "" ]; then
  cat /etc/os-release 2>/dev/null
  echo "!!! FAIL: Base Image cannot be detected or is not supported."
  exit 1
fi
echo "9) OPERATINGSYSTEM ---> '${baseimage}'"

# USER-CONFIRMATION
if [ "${noInteraction}" != "true" ]; then
  echo -n "# Do you agree with all parameters above? (yes/no) "
  read -r installRaspiblitzAnswer
  [ "$installRaspiblitzAnswer" != "yes" ] && exit 1
fi
echo "Building RaspiBlitz ..."
echo
sleep 3


# FIXING LOCALES
# https://github.com/rootzoll/raspiblitz/issues/138
# https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
# https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
if [ "${baseimage}" = "Raspbian" ] || [ "${baseimage}" = "DietPi" ] || \
   [ "${baseimage}" = "Raspios_arm64" ]||[ "${baseimage}" = "Debian_rpi64" ]; then
  echo
  echo "*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=en_US.UTF-8
  export LANG=en_US.UTF-8
  if [ "${baseimage}" = "Raspbian" ] || [ "${baseimage}" = "DietPi" ]; then
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
    echo "deb http://archive.raspberrypi.org/debian/ buster main" | sudo tee /etc/apt/sources.list.d/raspi.list
  fi
fi

echo "*** Remove not needed packages ***"
sudo apt remove -y --purge libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi minecraft-pi plymouth python2 vlc
sudo apt clean
sudo apt -y autoremove

echo
echo "*** Python DEFAULT libs & dependencies ***"

if [ -f "/usr/bin/python3.9" ]; then
  # use python 3.9 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  echo "python calls python3.9"
elif [ -f "/usr/bin/python3.10" ]; then
  # use python 3.10 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
  sudo ln -s /usr/bin/python3.10 /usr/bin/python3.9
  echo "python calls python3.10"
else
  echo "!!! FAIL !!!"
  echo "There is no tested version of python present"
  exit 1
fi

# for setup shell scripts
sudo apt -y install dialog bc python3-dialog

# libs (for global python scripts)
sudo -H python3 -m pip install --upgrade pip
sudo -H python3 -m pip install grpcio==1.42.0
sudo -H python3 -m pip install googleapis-common-protos==1.53.0
sudo -H python3 -m pip install toml==0.10.2
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
if [ "${baseimage}" = "Raspbian" ]||[ "${baseimage}" = "Raspios_arm64" ]||\
   [ "${baseimage}" = "Debian_rpi64" ]; then

  echo
  echo "*** PREPARE RASPBIAN ***"
  sudo apt install -y raspi-config
  # do memory split (16MB)
  sudo raspi-config nonint do_memory_split 16
  # set to wait until network is available on boot (0 seems to yes)
  sudo raspi-config nonint do_boot_wait 0
  # set WIFI country so boot does not block
  # this will undo the softblock of rfkill on RaspiOS
  [ "${modeWifi}" != "false" ] && sudo raspi-config nonint do_wifi_country $modeWifi
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


echo
echo "*** CONFIG ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#raspi-config

# set new default password for root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

# prepare auto-start of 00infoLCD.sh script on pi user login (just kicks in if auto-login of pi is activated in HDMI or LCD mode)
if [ "${baseimage}" = "Raspbian" ]||[ "${baseimage}" = "Raspios_arm64" ]||\
  [ "${baseimage}" = "Debian_rpi64" ]||[ "${baseimage}" = "Armbian" ]||\
  [ "${baseimage}" = "Ubuntu" ]; then
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
elif [ "${baseimage}" = "DietPi" ]; then
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
echo "
/var/log/syslog
{
	rotate 7
	daily
	missingok
	notifempty
	delaycompress
  compress
  postrotate
    invoke-rc.d rsyslog rotate > /dev/null
  endscript
}

/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
{
  rotate 4
  size=100M
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  postrotate
    invoke-rc.d rsyslog rotate > /dev/null
  enscript
}


/var/log/kern.log
/var/log/auth.log
{
        rotate 4
        size=100M
        missingok
        notifempty
        compress
        delaycompress
        sharedscripts
        postrotate
                invoke-rc.d rsyslog rotate > /dev/null
        endscript
}

/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
	rotate 4
	weekly
	missingok
	notifempty
	compress
	delaycompress
	sharedscripts
	postrotate
		invoke-rc.d rsyslog rotate > /dev/null
	endscript
}
" | sudo tee ./rsyslog
sudo mv ./rsyslog /etc/logrotate.d/rsyslog
sudo chown root:root /etc/logrotate.d/rsyslog
sudo service rsyslog restart

echo
echo "*** SOFTWARE UPDATE ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#software-update
# htop git curl bash-completion vim jq dphys-swapfile bsdmainutils -> helpers
# autossh telnet vnstat -> network tools bandwidth monitoring for future statistics
# parted dosfstolls -> prepare for format data drive
# btrfs-progs -> prepare for BTRFS data drive raid
# fbi -> prepare for display graphics mode. https://github.com/rootzoll/raspiblitz/pull/334
# sysbench -> prepare for powertest
# build-essential -> check for build dependencies on DietPi, Ubuntu, Armbian
general_utils="htop git curl bash-completion vim jq dphys-swapfile bsdmainutils autossh telnet vnstat parted dosfstools btrfs-progs fbi sysbench build-essential"

# dependencies for python
python_dependencies="python3-venv python3-dev python3-wheel python3-jinja2 python3-pip"

# add armbian-config
[ "${baseimage}" = "Armbian" ] && arbmbian_dependencies="armbian-config"

sudo apt install -y ${general_utils} ${python_dependencies} ${arbmbian_dependencies}

# make sure /usr/bin/pip exists (and calls pip3 in Debian Buster)
sudo update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# for TorBox bridges python scripts (pip3)
# https://github.com/radio24/TorBox/blob/master/requirements.txt
sudo pip install pytesseract
sudo pip install mechanize
sudo pip install PySocks
sudo pip install urwid
sudo pip install Pillow
sudo pip install requests
# setuptools needed for Nyx
sudo pip install setuptools

# rsync -> is needed to copy from HDD
# net-tools -> ifconfig
# xxd -> display hex codes
# netcat -> for 00infoBlitz.sh
# openssh-client openssh-sftp-server sshpass -> install OpenSSH client + server
# psmisc -> install killall, fuser
# ufw -> firewall
# sqlite3 -> database
sudo apt install -y rsync net-tools xxd netcat openssh-client openssh-sftp-server sshpass psmisc ufw sqlite3
sudo apt clean
sudo apt autoremove -y

echo
echo "*** ADDING MAIN USER admin ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#add-users
# using the default password 'raspiblitz'

sudo adduser --disabled-password --gecos "" admin
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
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#add-users

# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd

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
sudo -u admin rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b "${githubBranch}" https://github.com/${githubUser}/raspiblitz.git
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh
sudo -u admin chmod +x /home/admin/setup.scripts/*.sh

# install newest version of BlitzPy
blitzpy_wheel=$(ls -tR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E "any.whl" | tail -n 1)
blitzpy_version=$(echo "${blitzpy_wheel}" | grep -oE "([0-9]\.[0-9]\.[0-9])")
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
if [ "${baseimage}" == "Raspbian" ]; then
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
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo
echo "*** INCREASE OPEN FILE LIMIT ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_21_security.html#increase-your-open-files-limit

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

# *** Wifi, Bluetooth & other configs ***
if [ "${baseimage}" = "Raspbian" ]||[ "${baseimage}" = "Raspios_arm64"  ]||\
   [ "${baseimage}" = "Debian_rpi64" ]; then

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

  if [ "${disableBTDone}" -eq 0 ]; then
    # disable bluetooth module
    echo "" | sudo tee -a $configFile
    echo "# Raspiblitz" | sudo tee -a $configFile
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
  sudo sed -i "s/^dtoverlay=${dtoverlay}/# dtoverlay=${dtoverlay}/g" /boot/config.txt
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
  sudo apt install -y qrencode btrfs-tools secure-delete fbi ssmtp unclutter xterm python3-pyqt5 xfonts-terminus apache2-utils nginx python3-jinja2 socat libatlas-base-dev hexyl autossh

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

# "*** BITCOIN ***"

echo
echo "*** PREPARING BITCOIN ***"

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="22.0"

# needed to check code signing
# https://github.com/laanwj
laanwjPGP="71A3 B167 3540 5025 D447 E8F2 7481 0B01 2346 C9A6"

# prepare directories
sudo rm -rf /home/admin/download
sudo -u admin mkdir /home/admin/download
cd /home/admin/download || exit 1

# receive signer key
if ! gpg --keyserver hkp://keyserver.ubuntu.com --recv-key "71A3 B167 3540 5025 D447 E8F2 7481 0B01 2346 C9A6"
then
  echo "!!! FAIL !!! Couldn't download Wladimir J. van der Laan's PGP pubkey"
  exit 1
fi

# download signed binary sha256 hash sum file
sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS

# download signed binary sha256 hash sum file and check
sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | grep "${laanwjPGP}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo
  echo "!!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo
  echo "****************************************"
  echo "OK --> BITCOIN MANIFEST IS CORRECT"
  echo "****************************************"
  echo
fi

# bitcoinOSversion
if [ ${cpu} = "arm" ] ; then
  bitcoinOSversion="${cpu}-linux-gnueabihf"
else
  bitcoinOSversion="${cpu}-linux-gnu"
fi

echo
echo "*** BITCOIN CORE v${bitcoinVersion} for ${bitcoinOSversion} ***"

# download resources
binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
[ ! -f "./${binaryName}" ] && sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
if [ ! -f "./${binaryName}" ]; then
   echo "!!! FAIL !!! Could not download the BITCOIN BINARY"
   exit 1
else
  # check binary checksum test
  echo "- checksum test"
  # get the sha256 value for the corresponding platform from signed hash sum file
  bitcoinSHA256=$(grep -i "${binaryName}" SHA256SUMS | cut -d " " -f1)
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  echo "Valid SHA256 checksum should be: ${bitcoinSHA256}"
  echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
  if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
    echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
    rm -v ./${binaryName}
    exit 1
  else
    echo
    echo "********************************************"
    echo "OK --> VERIFIED BITCOIN CORE BINARY CHECKSUM"
    echo "********************************************"
    echo
    sleep 10
    echo
  fi
fi

# install
sudo -u admin tar -xvf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
sleep 3
installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
if [ ${installed} -lt 1 ]; then
  echo
  echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
  exit 1
fi
echo "- Bitcoin install OK"

echo
echo "*** PREPARING LIGHTNING ***"

# "*** LND ***"
## based on https://stadicus.github.io/RaspiBolt/raspibolt_40_lnd.html#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
## !!!! If you change here - make sure to also change interims version in lnd.update.sh !!!
lndVersion="0.13.3-beta"

# olaoluwa
PGPauthor="roasbeef"
PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
PGPcheck="E4D85299674B2D31FAA1892E372CBD7633C61696"
# bitconner
#PGPauthor="bitconner"
#PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# get LND resources
cd /home/admin/download || exit 1

# download lnd binary checksum manifest
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt

# check if checksums are signed by lnd dev team
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-${PGPauthor}-v${lndVersion}.sig
sudo -u admin wget --no-check-certificate -N -O "pgp_keys.asc" ${PGPpkeys}
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(sudo gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo
  echo "!!! BUILD WARNING --> LND PGP author not as expected"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read -r
fi
gpg --import ./pgp_keys.asc
sleep 3
verifyResult=$(gpg --verify manifest-${PGPauthor}-v${lndVersion}.sig manifest-v${lndVersion}.txt 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo
  echo "****************************************"
  echo "OK --> SIGNATURE LND MANIFEST IS CORRECT"
  echo "****************************************"
  echo
fi

# get the lndSHA256 for the corresponding platform from manifest file
lndSHA256=$(grep -i "linux-$architecture" manifest-v$lndVersion.txt | cut -d " " -f1)

echo
echo "*** LND v${lndVersion} for ${architecture} ***"
echo "SHA256 hash: $lndSHA256"
echo

# get LND binary
binaryName="lnd-linux-${architecture}-v${lndVersion}.tar.gz"
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
  echo
  echo "****************************************"
  echo "OK --> VERIFIED LND CHECKSUM IS CORRECT"
  echo "****************************************"
  echo
  sleep 10
fi

# install
echo "- install LND binary"
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-"${architecture}"-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi

correctVersion=$(sudo -u admin lnd --version | grep -c "${lndVersion}")
if [ "${correctVersion}" -eq 0 ]; then
  echo
  echo "!!! BUILD FAILED --> installed LND is not version ${lndVersion}"
  sudo -u admin lnd --version
  exit 1
fi
sudo chown -R admin /home/admin
echo "- OK install of LND done"

echo "*** C-lightning ***"
# https://github.com/ElementsProject/lightning/releases
CLVERSION=0.10.1

# https://github.com/ElementsProject/lightning/tree/master/contrib/keys
PGPsigner="rustyrussel"
PGPpkeys="https://raw.githubusercontent.com/ElementsProject/lightning/master/contrib/keys/rustyrussell.txt"
PGPcheck="D9200E6CD1ADB8F1"

# prepare download dir
sudo rm -rf /home/admin/download/cl
sudo -u admin mkdir -p /home/admin/download/cl
cd /home/admin/download/cl || exit 1

sudo -u admin wget -O "pgp_keys.asc" ${PGPpkeys}
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo
  echo "!!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read -r
fi
gpg --import ./pgp_keys.asc

sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/v${CLVERSION}/SHA256SUMS
sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/v${CLVERSION}/SHA256SUMS.asc

verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)

goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo
  echo "!!! BUILD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo
  echo "****************************************************************"
  echo "OK --> the PGP signature of the C-lightning SHA256SUMS is correct"
  echo "****************************************************************"
  echo
fi

sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/v${CLVERSION}/clightning-v${CLVERSION}.zip

hashCheckResult=$(sha256sum -c SHA256SUMS 2>&1)
goodHash=$(echo ${hashCheckResult} | grep 'OK' -c)
echo "goodHash(${goodHash})"
if [ ${goodHash} -lt 1 ]; then
  echo
  echo "!!! BUILD FAILED --> Hash check not OK"
  exit 1
else
  echo
  echo "********************************************************************"
  echo "OK --> the hash of the downloaded C-lightning source code is correct"
  echo "********************************************************************"
  echo
fi

echo "- Install build dependencies"
sudo apt install -y \
  autoconf automake build-essential git libtool libgmp-dev \
  libsqlite3-dev python3 python3-mako net-tools zlib1g-dev libsodium-dev \
  gettext unzip

sudo -u admin unzip clightning-v${CLVERSION}.zip
cd clightning-v${CLVERSION} || exit 1

echo "- Configuring EXPERIMENTAL_FEATURES enabled"
sudo -u admin ./configure --enable-experimental-features

echo "- Building C-lightning from source"
sudo -u admin make

echo "- Install to /usr/local/bin/"
sudo make install || exit 1

installed=$(sudo -u admin lightning-cli --version)
if [ ${#installed} -eq 0 ]; then
  echo
  echo "!!! BUILD FAILED --> Was not able to install C-lightning"
  exit 1
fi

correctVersion=$(echo "${installed}" | grep -c "${CLVERSION}")
if [ ${correctVersion} -eq 0 ]; then
  echo
  echo "!!! BUILD FAILED --> installed C-lightning is not version ${CLVERSION}"
  sudo -u admin lightning-cli --version
  exit 1
fi
echo "- OK the installation of C-lightning v${installed} is done"

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
if [ "${displayClass}" != "headless" ] || [ "${baseimage}" = "Raspbian" ] || [ "${baseimage}" = "Raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blitz.display.sh set-display ${displayClass}"
  sudo /home/admin/config.scripts/blitz.display.sh set-display ${displayClass}
  sudo /home/admin/config.scripts/blitz.display.sh rotate 1
fi

echo "# BUILD DONE - see above"
