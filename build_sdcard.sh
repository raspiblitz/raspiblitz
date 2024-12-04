#!/usr/bin/env bash

#########################################################################
# Build your SD card image based on: 2024-03-15-raspios-bookworm-arm64.img.xz
# https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2024-03-15/
# SHA256: 7e53a46aab92051d523d7283c080532bebb52ce86758629bf1951be9b4b0560f
# also change in: raspiblitz/ci/arm64-rpi/build.arm64-rpi.pkr.hcl
# PGP fingerprint: 8738CD6B956F460C - to check signature:
# curl -O https://www.raspberrypi.org/raspberrypi_downloads.gpg.key && gpg --import ./raspberrypi_downloads.gpg.key && gpg --verify *.sig
# setup fresh SD card with image above - login via SSH and run this script:
##########################################################################

# set locale to en_US.UTF-8 on system & activate for this script
echo "# updating locale ..."
sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
locale-gen en_US.UTF-8 en_US ISO-8859-1 1>/dev/null
update-locale LANG=en_US.UTF-8 1>/dev/null
source /etc/default/locale

defaultRepo="raspiblitz" # user that hosts a `raspiblitz` repo
defaultBranch="v1.11" # latest version branch

defaultAPIuser="fusion44"
defaultAPIrepo="blitz_api"

defaultWEBUIuser="raspiblitz"
defaultWEBUIrepo="raspiblitz-web"

me="${0##/*}"

nocolor="\033[0m"
red="\033[31m"

## usage as a function to be called whenever there is a huge mistake on the options
usage(){
  printf %s"${me} [--option <argument>]

Options:
  -EXPORT                                  just print build parameters & exit'
  -h, --help                               this help info
  -i, --interaction [0|1]                  interaction before proceeding with execution (default: 1)
  -f, --fatpack [0|1]                      fatpack mode (default: 1)
  -u, --github-user [raspiblitz|other]     github user to be checked from the repo (default: ${defaultRepo})
  -b, --branch [v1.7|v1.8]                 branch to be built on (default: ${defaultBranch})
  -d, --display [lcd|hdmi|headless]        display class (default: lcd)
  -t, --tweak-boot-drive [0|1]             tweak boot drives (default: 1)
  -w, --wifi-region [off|US|GB|other]      wifi iso code (default: US) or 'off'

Notes:
  all options, long and short accept --opt=value mode also
  [0|1] can also be referenced as [false|true]
"
  exit 1
}
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root / may use sudo'"
  exit 1
fi

# Check if /usr/sbin is not in the PATH and add it if necessary
if [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
    export PATH="$PATH:/usr/sbin"
fi

# Check if /usr/bin is not in the PATH and add it if necessary
if [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="$PATH:/usr/bin"
fi

if [ "$1" = "-EXPORT" ] || [ "$1" = "EXPORT" ]; then
  activeBranch=$(git -C /home/admin/raspiblitz branch --show-current 2>/dev/null)
  echo "activeBranch='${activeBranch}'"
  if [ "${activeBranch}" == "" ]; then
    activeBranch="${defaultBranch}"
  fi
  echo "githubUser='${defaultRepo}'"
  echo "githubBranch='${activeBranch}'"
  echo "defaultAPIuser='${defaultAPIuser}'"
  echo "defaultAPIrepo='${defaultAPIrepo}'"
  echo "defaultWEBUIuser='${defaultWEBUIuser}'"
  echo "defaultWEBUIrepo='${defaultWEBUIrepo}'"
  exit 0
fi

## default user message
error_msg(){ printf %s"${red}${me}: ${1}${nocolor}\n"; exit 1; }

## assign_value variable_name "${opt}"
## it strips the dashes and assign the clean value to the variable
## assign_value status --on IS status=on
## variable_name is the name you want it to have
## $opt being options with single or double dashes that don't require arguments
assign_value(){
  case "${2}" in
    --*) value="${2#--}";;
    -*) value="${2#-}";;
    *) value="${2}"
  esac
  case "${value}" in
    0) value="false";;
    1) value="true";;
  esac
  ## Escaping quotes is needed because else if will fail if the argument is quoted
  # shellcheck disable=SC2140
  eval "${1}"="\"${value}\""
}

## get_arg variable_name "${opt}" "${arg}"
## get_arg service --service ssh
## variable_name is the name you want it to have
## $opt being options with single or double dashes
## $arg is requiring and argument, else it fails
## assign_value "${1}" "${3}" means it is assining the argument ($3) to the variable_name ($1)
get_arg(){
  case "${3}" in
    ""|-*) error_msg "Option '${2}' requires an argument.";;
  esac
  assign_value "${1}" "${3}"
}

## hacky getopts
## 1. if the option requires an argument, and the option is preceeded by single or double dash and it
##    can be it can be specified with '-s=ssh' or '-s ssh' or '--service=ssh' or '--service ssh'
##    use: get_arg variable_name "${opt}" "${arg}"
## 2. if a bunch of options that does different things are to be assigned to the same variable
##    and the option is preceeded by single or double dash use: assign_value variable_name "${opt}"
##    as this option does not require argument, specifu $shift_n=1
## 3. if the option does not start with dash and does not require argument, assign to command manually.
while :; do
  case "${1}" in
    -*=*) opt="${1%=*}"; arg="${1#*=}"; shift_n=1;;
    -*) opt="${1}"; arg="${2}"; shift_n=2;;
    *) opt="${1}"; arg="${2}"; shift_n=1;;
  esac
  case "${opt}" in
    -i|-i=*|--interaction|--interaction=*) get_arg interaction "${opt}" "${arg}";;
    -f|-f=*|--fatpack|--fatpack=*) get_arg fatpack "${opt}" "${arg}";;
    -u|-u=*|--github-user|--github-user=*) get_arg github_user "${opt}" "${arg}";;
    -b|-b=*|--branch|--branch=*) get_arg branch "${opt}" "${arg}";;
    -d|-d=*|--display|--display=*) get_arg display "${opt}" "${arg}";;
    -t|-t=*|--tweak-boot-drive|--tweak-boot-drive=*) get_arg tweak_boot_drive "${opt}" "${arg}";;
    -w|-w=*|--wifi-region|--wifi-region=*) get_arg wifi_region "${opt}" "${arg}";;
    "") break;;
    *) error_msg "Invalid option: ${opt}";;
  esac
  shift "${shift_n}"
done

## if there is a limited option, check if the value of variable is within this range
## $ range_argument variable_name possible_value_1 possible_value_2
range_argument(){
  name="${1}"
  eval var='$'"${1}"
  shift
  if [ -n "${var:-}" ]; then
    success=0
    for tests in "${@}"; do
      [ "${var}" = "${tests}" ] && success=1
    done
    [ ${success} -ne 1 ] && error_msg "Option '--${name}' cannot be '${var}'! It can only be: ${*}."
  fi
}

apt_install() {
  for package in "$@"; do
    apt-get install -y -q "$package"
    if [ $? -eq 100 ]; then
      echo "FAIL! apt-get failed to install package: $package"
      exit 1
    fi
  done
}

general_utils="curl"
## loop through all general_utils to see if program is installed (placed on PATH) and if not, add to the list of commands to be installed
for prog in ${general_utils}; do
  ! command -v ${prog} >/dev/null && general_utils_install="${general_utils_install} ${prog}"
done
## if any of the required programs are not installed, update and if successfull, install packages
if [ -n "${general_utils_install}" ]; then
  echo -e "\n*** SOFTWARE UPDATE ***"
  apt-get update -y || exit 1
  apt_install ${general_utils_install}
fi

## use default values for variables if empty

# INTERACTION
# ----------------------------------------
# When 'false' then no questions will be asked on building .. so it can be used in build scripts
# for containers or as part of other build scripts (default is true)
: "${interaction:=true}"
range_argument interaction "0" "1" "false" "true"

# FATPACK
# -------------------------------
# could be 'true' (default) or 'false'
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...
: "${fatpack:=true}"
range_argument fatpack "0" "1" "false" "true"

# GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblitz repo - 'rootzoll' is default
# The 'raspiblitz' repo of this user is used to provisioning sd card with raspiblitz assets/scripts later on.
: "${github_user:=$defaultRepo}"
curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${github_user}/raspiblitz" | grep -q "\"message\": \"Not Found\"" && error_msg "Repository 'raspiblitz' not found for user '${github_user}"

# GITHUB-BRANCH
# -------------------------------------
# could be any valid branch or tag of the given GITHUB-USERNAME forked raspiblitz repo
: "${branch:=$defaultBranch}"
curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${github_user}/raspiblitz/branches/${branch}" | grep -q "\"message\": \"Branch not found\"" && error_msg "Repository 'raspiblitz' for user '${github_user}' does not contain branch '${branch}'"

# DISPLAY-CLASS
# ----------------------------------------
# Could be 'hdmi', 'headless' or 'lcd' (lcd is default)
: "${display:=lcd}"
range_argument display "lcd" "hdmi" "headless"

# TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
: "${tweak_boot_drive:=true}"
range_argument tweak_boot_drive "0" "1" "false" "true"

# WIFI
# ---------------------------------------
# WIFI country code like 'US' (default)
# If any valid wifi country code Wifi will be activated with that country code by default
: "${wifi_region:=US}"

echo "*****************************************"
echo "*     RASPIBLITZ SD CARD IMAGE SETUP    *"
echo "*****************************************"
echo "For details on optional parameters - call with '--help' or check source code."

# output
for key in interaction fatpack github_user branch display tweak_boot_drive wifi_region; do
  eval val='$'"${key}"
  [ -n "${val}" ] && printf '%s\n' "${key}=${val}"
done

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
cpu="$(uname -m)" && echo "cpu=${cpu}"
case "${cpu}" in
  aarch64|x86_64);;
  *) echo -e "# FAIL #\nCan only build on aarch64 or x86_64 not on: cpu=${cpu}"; exit 1;;
esac
architecture="$(dpkg --print-architecture 2>/dev/null)" && echo "architecture=${architecture}"
case "${architecture}" in
  arm*|amd64);;
  *) echo -e "# FAIL #\nCan only build on arm* or amd64 not on: architecture=${cpu}"; exit 1;;
esac

# AUTO-DETECTION: OPERATINGSYSTEM
# ---------------------------------------
if [ $(cat /etc/os-release 2>/dev/null | grep -c 'Debian') -gt 0 ]; then
  if [ -f /etc/apt/sources.list.d/raspi.list ] && [ "${cpu}" = aarch64 ]; then
    # default image for RaspberryPi
    baseimage="raspios_arm64"
  else
    # experimental: fallback for all to debian
    baseimage="debian"
  fi
elif [ $(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu') -gt 0 ]; then
  baseimage="ubuntu"
elif [ $(cat /etc/os-release 2>/dev/null | grep -c 'Armbian') -gt 0 ]; then
  baseimage="armbian"
else
  echo "\n# FAIL: Base Image cannot be detected or is not supported."
  cat /etc/os-release 2>/dev/null
  uname -a
  exit 1
fi
echo "baseimage=${baseimage}"

# AUTO-DETECTION: CONFIGFILES
# ---------------------------------------
raspi_configfile="/boot/config.txt"
raspi_commandfile="/boot/cmdline.txt"
if [ -d /boot/firmware ];then
  raspi_configfile="/boot/firmware/config.txt" 
  raspi_commandfile="/boot/firmware/cmdline.txt"
fi
echo "raspi_configfile=${raspi_configfile}"
echo "raspi_commandfile=${raspi_commandfile}"

# USER-CONFIRMATION
if [ "${interaction}" = "true" ]; then
  echo -n "# Do you agree with all parameters above? (yes/no) "
  read -r installRaspiblitzAnswer
  [ "$installRaspiblitzAnswer" != "yes" ] && exit 1
fi
echo -e "Building RaspiBlitz ...\n"
sleep 3 ## give time to cancel

export DEBIAN_FRONTEND=noninteractive

echo "*** Prevent sleep ***" # on all platforms https://wiki.debian.org/Suspend
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
mkdir /etc/systemd/sleep.conf.d
echo "[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no" | tee /etc/systemd/sleep.conf.d/nosuspend.conf
mkdir /etc/systemd/logind.conf.d
echo "[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore" | tee /etc/systemd/logind.conf.d/nosuspend.conf

# check if /etc/hosts already has debian entry
# prevent "unable to resolve host debian" error
isDebianInHosts=$(grep -c "debian" /etc/hosts)
if [ ${isDebianInHosts} -eq 0 ]; then
  echo "# Adding debian to /etc/hosts"
  echo "127.0.1.1       debian" | tee -a /etc/hosts > /dev/null
  if [ "${baseimage}" != "raspios_arm64" ]; then
    systemctl restart networking
  fi
fi

echo "*** Remove unnecessary packages ***"
unnecessary_packages=(libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi plymouth python2 vlc* cups)
for pkg in "${unnecessary_packages[@]}"; do
  if dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -q "ok installed"; then
    echo "Removing $pkg..."
    apt-get remove --purge -y $pkg
  else
    echo "$pkg is not installed."
  fi
done
apt-get clean -y
apt-get autoremove -y

grep -q "^nameserver 8.8.8.8$" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo -e "\n*** UPDATE Debian***"
apt-get update -y
apt-get upgrade -f -y

echo -e "\n*** SOFTWARE UPDATE ***"
# based on https://raspibolt.org/system-configuration.html#system-update
# htop git curl bash-completion vim jq dphys-swapfile bsdmainutils -> helpers
# autossh telnet vnstat -> network tools bandwidth monitoring for future statistics
# parted dosfstools -> prepare for format data drive
# btrfs-progs -> prepare for BTRFS data drive raid
# fbi -> prepare for display graphics mode. https://github.com/rootzoll/raspiblitz/pull/334
# sysbench -> prepare for powertest
# build-essential -> check for build dependencies on Ubuntu, Armbian
# dialog -> dialog bc python3-dialog
# rsync -> is needed to copy from HDD
# net-tools -> ifconfig
# xxd -> display hex codes
# netcat-openbsd -> for proxy
# openssh-client openssh-sftp-server sshpass -> install OpenSSH client + server
# psmisc -> install killall, fuser
# ufw -> firewall
# sqlite3 -> database
# fdisk -> create partitions
# lsb-release -> needed to know which distro version we're running to add APT sources
general_utils="sudo policykit-1 htop git curl bash-completion vim jq dphys-swapfile bsdmainutils autossh telnet vnstat parted dosfstools fbi sysbench build-essential dialog bc python3-dialog unzip whois fdisk lsb-release smartmontools rsyslog"
# add btrfs-progs if not bookworm on aarch64
[ "${architecture}" = "aarch64" ] && ! grep "12 (bookworm)" < /etc/os-release && general_utils="${general_utils} btrfs-progs"
# python3-mako --> https://github.com/rootzoll/raspiblitz/issues/3441
python_dependencies="python3-venv python3-dev python3-wheel python3-jinja2 python3-pip python3-mako"
server_utils="rsync net-tools xxd netcat-openbsd openssh-client openssh-sftp-server sshpass psmisc ufw sqlite3"
[ "${baseimage}" = "armbian" ] && armbian_dependencies="armbian-config" # add armbian-config
[ "${architecture}" = "amd64" ] && amd64_dependencies="network-manager" # add amd64 dependency

apt_install resolvconf
/sbin/resolvconf -u
apt_install ${general_utils} ${python_dependencies} ${server_utils} ${amd64_dependencies} ${armbian_dependencies}
apt-get clean -y
apt-get autoremove -y

echo -e "\n*** Python DEFAULT libs & dependencies ***"

if [ -f "/usr/bin/python3.11" ]; then
  # use python 3.11 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
  # keep python backwards compatible
  ln -s /usr/bin/python3.11 /usr/bin/python3.9
  ln -s /usr/bin/python3.11 /usr/bin/python3.10
  echo "python calls python3.11"
elif [ -f "/usr/bin/python3.10" ]; then
  # use python 3.10 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
  # keep python backwards compatible
  ln -s /usr/bin/python3.10 /usr/bin/python3.9
  echo "python calls python3.10"
elif [ -f "/usr/bin/python3.9" ]; then
  # use python 3.9 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  echo "python calls python3.9"
elif [ -f "/usr/bin/python3.8" ]; then
  # use python 3.8 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  echo "python calls python3.8"
else
  echo "# FAIL #"
  echo "There is no tested version of python present"
  exit 1
fi

# don't protect system packages from pip install
# tracking issue: https://github.com/raspiblitz/raspiblitz/issues/4170
for PYTHONDIR in /usr/lib/python3.*; do
  if [ -f "$PYTHONDIR/EXTERNALLY-MANAGED" ]; then
    rm "$PYTHONDIR/EXTERNALLY-MANAGED"
  fi
done

# make sure /usr/bin/pip exists (and calls pip3 in Debian Buster)
update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1
# 1. libs (for global python scripts)
# grpcio==1.59.3 googleapis-common-protos==1.61.0 toml==0.10.2 j2cli==0.3.10 requests[socks]==2.21.0 protobuf==4.25.1 pathlib2==2.3.7.post1
# 2. For TorBox bridges python scripts (pip3) https://github.com/radio24/TorBox/blob/master/requirements.txt
# pytesseract mechanize PySocks urwid Pillow requests
# 3. Nyx
# setuptools
sudo -H python3 -m pip install --upgrade pip
sudo -H python3 -m pip install grpcio==1.59.3 googleapis-common-protos==1.61.0 toml==0.10.2 j2cli==0.3.10 requests[socks]==2.21.0 protobuf==4.25.1 pathlib2==2.3.7.post1
sudo -H python3 -m pip install pytesseract mechanize PySocks urwid Pillow requests setuptools

echo -e "\n*** PREPARE ${baseimage} ***"

# make sure the pi user is present
if ! compgen -u pi; then
  echo "# Adding the user pi"
  adduser --system --group --shell /bin/bash --home /home/pi pi
  # copy the skeleton files for login
  sudo -u pi cp -r /etc/skel/. /home/pi/
  adduser pi sudo
fi

# activate watchdog if ls /dev/watchdog exists - see #4534
if [ -e /dev/watchdog ]; then
  echo "Activating watchdog ..."
  if [ "${baseimage}" = "raspios_arm64" ]; then
    echo "dtparam=watchdog=on" | tee -a $raspi_configfile
  fi
  sed -i "s/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=600s/g" /etc/systemd/system.conf
  sed -i "s/^#RebootWatchdogSec=.*/RebootWatchdogSec=3min/g" /etc/systemd/system.conf
  sed -i "s/^#WatchdogDevice=.*/WatchdogDevice=\/dev\/watchdog/g" /etc/systemd/system.conf
else
  echo "No watchdog device /dev/watchdog found - keep watchdog like default"
fi

# special prepare when RaspberryPi OS
if [ "${baseimage}" = "raspios_arm64" ]; then

  echo -e "\n*** PREPARE RASPBERRY OS VARIANTS ***"
  apt_install raspi-config
  # set WIFI country so boot does not block
  # this will undo the softblock of rfkill on RaspiOS
  [ "${wifi_region}" != "off" ] && raspi-config nonint do_wifi_country $wifi_region
  # see https://github.com/rootzoll/raspiblitz/issues/428#issuecomment-472822840

  if ! grep "Raspiblitz" $raspi_configfile; then
    echo "# Adding Raspiblitz Edits to $raspi_configfile"
    echo | tee -a $raspi_configfile
    echo "# Raspiblitz" | tee -a $raspi_configfile
    # ensure that kernel8.img is used to set PAGE_SIZE to 4K
    # https://github.com/raspiblitz/raspiblitz/issues/4346
    if [ -f /boot/kernel8.img ] || [ -f /boot/firmware/kernel8.img ]; then
      echo 'kernel=kernel8.img' | tee -a $raspi_configfile
    fi
    echo "max_usb_current=1" | tee -a $raspi_configfile
    echo "dtparam=nvme" | tee -a $raspi_configfile
    echo 'dtoverlay=pi3-disable-bt' | tee -a $raspi_configfile
    echo 'dtoverlay=disable-bt' | tee -a $raspi_configfile
  else
    echo "# Raspiblitz Edits are already in $raspi_configfile"
  fi

  # run fsck on sd root partition on every startup to prevent "maintenance login" screen
  # see: https://github.com/rootzoll/raspiblitz/issues/782#issuecomment-564981630
  # see https://github.com/rootzoll/raspiblitz/issues/1053#issuecomment-600878695
  # use command to check last fsck check: tune2fs -l /dev/mmcblk0p2
  if [ "${tweak_boot_drive}" == "true" ]; then
    echo "* running tune2fs"
    tune2fs -c 1 /dev/mmcblk0p2
  else
    echo "* skipping tweak_boot_drive"
  fi

  # edit kernel parameters
  fsOption1="fsck.mode=force"
  fsOption2="fsck.repair=yes"
  fsOption1InFile=$(grep -c ${fsOption1} ${raspi_commandfile})
  fsOption2InFile=$(grep -c ${fsOption2} ${raspi_commandfile})

  if [ ${fsOption1InFile} -eq 0 ]; then
    sed -i "s/^/$fsOption1 /g" "${raspi_commandfile}"
    echo "$fsOption1 added to ${raspi_commandfile}"
  else
    echo "$fsOption1 already in ${raspi_commandfile}"
  fi
  if [ ${fsOption2InFile} -eq 0 ]; then
    sed -i "s/^/$fsOption2 /g" "${raspi_commandfile}"
    echo "$fsOption2 added to ${raspi_commandfile}"
  else
    echo "$fsOption2 already in ${raspi_commandfile}"
  fi

  # *** SAFE SHUTDOWN ***
  # logind
  echo "[Login]" | tee /etc/systemd/logind.conf.d/safeshutdown.conf
  echo "HandlePowerKey=ignore" | tee -a /etc/systemd/logind.conf.d/safeshutdown.conf
  # sudoers
  echo 'nobody ALL=(ALL) NOPASSWD: /home/admin/config.scripts/blitz.shutdown.sh' |
    tee -a /etc/sudoers
  # triggerhappy
  echo 'KEY_POWER    1    sudo /home/admin/config.scripts/blitz.shutdown.sh' |
    tee /etc/triggerhappy/triggers.d/powerbutton.conf
fi

# special prepare when Nvidia Jetson Nano
if [ $(uname -a | grep -c 'tegra') -gt 0 ] ; then
  echo "Nvidia --> disable GUI on boot"
  systemctl set-default multi-user.target
fi

# remove rpi-first-boot-wizard
apt purge piwiz -y
userdel -r rpi-first-boot-wizard

echo -e "\n*** CONFIG ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#raspi-config

# set new default password for root user
echo "root:raspiblitz" | chpasswd
echo "pi:raspiblitz" | chpasswd

# prepare auto-start of 00infoLCD.sh script on pi user login (just kicks in if auto-login of pi is activated in HDMI or LCD mode)
if [ "${baseimage}" = "raspios_arm64" ] || [ "${baseimage}" = "debian" ] || [ "${baseimage}" = "ubuntu" ]; then
  homeFile=/home/pi/.bashrc
  autostartDone=$(grep -c "automatic start the LCD" $homeFile)
  if [ ${autostartDone} -eq 0 ]; then
    # bash autostart for pi
    # run as exec to dont allow easy physical access by keyboard
    # see https://github.com/rootzoll/raspiblitz/issues/54
    bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
    bash -c 'echo "SCRIPT=\"sudo /home/admin/00infoLCD.sh\"" >> /home/pi/.bashrc'
    bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
    bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'
    echo "autostart LCD added to $homeFile"
  else
    echo "autostart LCD already in $homeFile"
  fi
else
  echo "WARN: Script Autostart not available for baseimage(${baseimage}) - may just run on 'headless'"
fi

# limit journald system use
sed -i "s/^#SystemMaxUse=.*/SystemMaxUse=250M/g" /etc/systemd/journald.conf
sed -i "s/^#SystemMaxFileSize=.*/SystemMaxFileSize=50M/g" /etc/systemd/journald.conf

## LOG ROTATION

# GLOBAL for all logs: /etc/logrotate.conf
echo "# Optimizing log files: rotate daily max 100M, keep 4 days & compress old"
sed -i "s/^weekly/daily size 100M/g" /etc/logrotate.conf
sed -i "s/^#compress/compress/g" /etc/logrotate.conf

# add the option "copytruncate" to /etc/logrotate.conf below the line staring with "# global options do"
sed -i '/# global options do/a \copytruncate' /etc/logrotate.conf

# SPECIAL FOR SYSLOG: /etc/logrotate.d/rsyslog
# to test config run: sudo logrotate -v /etc/logrotate.d/rsyslog
rm /etc/logrotate.d/rsyslog 2>/dev/null
echo "
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
  rotate 4
  size 100M
  missingok
  compress
  delaycompress
  copytruncate
  sharedscripts
  postrotate
    service logrotate restart
  endscript
}
" | tee ./rsyslog
mv ./rsyslog /etc/logrotate.d/rsyslog
chown root:root /etc/logrotate.d/rsyslog
service logrotate restart
service rsyslog restart

echo -e "\n*** ADDING MAIN USER admin ***"
# based on https://raspibolt.org/system-configuration.html#add-users
# using the default password 'raspiblitz'
adduser --disabled-password --gecos "" admin
# make the home folder world readable
chmod 0755 /home/admin
echo "admin:raspiblitz" | chpasswd
adduser admin sudo
chsh admin -s /bin/bash
# configure sudo for usage without password entry
echo '%sudo ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo
# check if group "admin" was created
if [ $(sudo cat /etc/group | grep -c "^admin") -lt 1 ]; then
  echo -e "\nMissing group admin - creating it ..."
  groupadd --force --gid 1002 admin
  usermod -a -G admin admin
else
  echo -e "\nOK group admin exists"
fi

echo -e "\n*** ADDING SERVICE USER bitcoin"
# based on https://raspibolt.org/guide/raspberry-pi/system-configuration.html
# create user and set default password for user
adduser --system --group --shell /bin/bash --home /home/bitcoin bitcoin
# copy the skeleton files for login
sudo -u bitcoin cp -r /etc/skel/. /home/bitcoin/
echo "bitcoin:raspiblitz" | chpasswd
# make home directory readable
chmod 755 /home/bitcoin

# WRITE BASIC raspiblitz.info to sdcard
# if further info gets added .. make sure to keep that on: blitz.release.sh
touch /home/admin/raspiblitz.info
echo "baseimage=${baseimage}" | tee raspiblitz.info
echo "cpu=${cpu}" | tee -a raspiblitz.info
echo "displayClass=headless" | tee -a raspiblitz.info
mv raspiblitz.info /home/admin/
chmod 755 /home/admin/raspiblitz.info
chown admin:admin /home/admin/raspiblitz.info

echo -e "\n*** ADDING GROUPS FOR CREDENTIALS STORE ***"
# access to credentials (e.g. macaroon files) in a central location is managed with unix groups and permissions
groupadd --force --gid 9700 lndadmin
groupadd --force --gid 9701 lndinvoice
groupadd --force --gid 9702 lndreadonly
groupadd --force --gid 9703 lndinvoices
groupadd --force --gid 9704 lndchainnotifier
groupadd --force --gid 9705 lndsigner
groupadd --force --gid 9706 lndwalletkit
groupadd --force --gid 9707 lndrouter

echo -e "\n*** SHELL SCRIPTS & ASSETS ***"
# copy raspiblitz repo from github
cd /home/admin/ || exit 1
sudo -u admin git config --global user.name "${github_user}" || exit 1
sudo -u admin git config --global user.email "johndoe@example.com" || exit 1
sudo -u admin git config --global http.postBuffer 524288000 || exit 1
sudo -u admin rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b "${branch}" https://github.com/${github_user}/raspiblitz.git || exit 1
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/*.* /home/admin || exit 1
sudo -u admin cp /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin || exit 1
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/ || exit 1
sudo -u admin chmod +x *.sh || exit 1
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/ || exit 1
sudo -u admin chmod +x /home/admin/config.scripts/*.sh || exit 1
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/setup.scripts /home/admin/ || exit 1
sudo -u admin chmod +x /home/admin/setup.scripts/*.sh || exit 1

# install newest version of BlitzPy
blitzpy_wheel=$(ls -tR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E "any.whl" | tail -n 1)
blitzpy_version=$(echo "${blitzpy_wheel}" | grep -oE "([0-9]\.[0-9]\.[0-9])")
echo -e "\n*** INSTALLING BlitzPy Version: ${blitzpy_version} ***"
sudo -H /usr/bin/python -m pip install "/home/admin/raspiblitz/home.admin/BlitzPy/dist/${blitzpy_wheel}" >/dev/null 2>&1

# make sure lndlibs are patched for compatibility for both Python2 and Python3
file="/home/admin/config.scripts/lndlibs/lightning_pb2_grpc.py"
! grep -Fxq "from __future__ import absolute_import" "${file}" && sed -i -E '1 a from __future__ import absolute_import' "${file}"
! grep -Eq "^from . import.*" "${file}" && sed -i -E 's/^(import.*_pb2)/from . \1/' "${file}"

# add /sbin to path for all
bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

# replace boot splash image when raspbian
[ -d /usr/share/plymouth ] && [ "${baseimage}" = "raspios_arm64" ] && { echo "* replacing boot splash"; cp /home/admin/raspiblitz/pictures/splash.png /usr/share/plymouth/themes/pix/splash.png; }

echo -e "\n*** RASPIBLITZ EXTRAS ***"

# screen for background processes
# tmux for multiple (detachable/background) sessions when using SSH https://github.com/rootzoll/raspiblitz/issues/990
# fzf install a command-line fuzzy finder (https://github.com/junegunn/fzf)
apt_install tmux screen fzf

bash -c "echo '' >> /home/admin/.bashrc"
bash -c "echo '# https://github.com/rootzoll/raspiblitz/issues/1784' >> /home/admin/.bashrc"
bash -c "echo 'NG_CLI_ANALYTICS=ci' >> /home/admin/.bashrc"

# raspiblitz custom command prompt #2400
if ! grep -Eq "^[[:space:]]*PS1.*₿" /home/admin/.bashrc; then
    sed -i '/^unset color_prompt force_color_prompt$/i # raspiblitz custom command prompt https://github.com/rootzoll/raspiblitz/issues/2400' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i raspiIp=$(hostname -I | cut -d " " -f1)' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i if [ "$color_prompt" = yes ]; then' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\[\\033[00;33m\\]\\u@$raspiIp:\\[\\033[00;34m\\]\\w\\[\\033[01;35m\\]$(__git_ps1 "(%s)") \\[\\033[01;33m\\]₿\\[\\033[00m\\] \x27' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i else' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\u@$raspiIp:\\w₿ \x27' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i fi' /home/admin/.bashrc
fi

echo -e "\n*** FUZZY FINDER KEY BINDINGS ***"
homeFile=/home/admin/.bashrc
keyBindingsDone=$(grep -c "source /usr/share/doc/fzf/examples/key-bindings.bash" $homeFile)
if [ ${keyBindingsDone} -eq 0 ]; then
  bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"
  echo "key-bindings added to $homeFile"
else
  echo "key-bindings already in $homeFile"
fi

echo -e "\n*** AUTOSTART ADMIN SSH MENUS ***"
homeFile=/home/admin/.bashrc
autostartDone=$(grep -c "automatically start main menu" $homeFile)
if [ ${autostartDone} -eq 0 ]; then
  # bash autostart for admin
  bash -c "echo '# shortcut commands' >> /home/admin/.bashrc"
  bash -c "echo 'source /home/admin/_commands.sh' >> /home/admin/.bashrc"
  bash -c "echo '# automatically start main menu for admin unless' >> /home/admin/.bashrc"
  bash -c "echo '# when running in a tmux session' >> /home/admin/.bashrc"
  bash -c "echo 'if [ -z \"\$TMUX\" ]; then' >> /home/admin/.bashrc"
  bash -c "echo '    ./00raspiblitz.sh newsshsession' >> /home/admin/.bashrc"
  bash -c "echo 'fi' >> /home/admin/.bashrc"
  echo "autostart added to $homeFile"
else
  echo "autostart already in $homeFile"
fi

echo -e "\n*** SWAP FILE ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)
dphys-swapfile swapoff
dphys-swapfile uninstall

echo -e "\n*** INCREASE OPEN FILE LIMIT ***"
# based on https://raspibolt.org/guide/raspberry-pi/security.html#increase-your-open-files-limit
sed --in-place -i "56s/.*/*    soft nofile 256000/" /etc/security/limits.conf
bash -c "echo '*    hard nofile 256000' >> /etc/security/limits.conf"
bash -c "echo 'root soft nofile 256000' >> /etc/security/limits.conf"
bash -c "echo 'root hard nofile 256000' >> /etc/security/limits.conf"
bash -c "echo '# End of file' >> /etc/security/limits.conf"
sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session
sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"

# Increase maximum number of inotify instances
bash -c "echo '# RaspiBlitz Edit: Set maximum number of inotify instances (8192 recommended for min 2GB RAM)' >> /etc/sysctl.conf"
bash -c "echo 'fs.inotify.max_user_instances=8192' >> /etc/sysctl.conf"

# Activate overcommit_memory
bash -c "echo '# RaspiBlitz Edit: Use overcommit to prevent system crashes' >> /etc/sysctl.conf"
bash -c "echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf"

# *** fail2ban ***
# based on https://raspibolt.org/security.html#fail2ban
echo "*** HARDENING ***"
apt_install --no-install-recommends python3-systemd fail2ban
# https://github.com/raspiblitz/raspiblitz/issues/4044
if [ ! -f /var/log/auth.log ]; then
  touch /var/log/auth.log
fi

# *** CACHE DISK IN RAM & KEYVALUE-STORE***
echo "Activating CACHE RAM DISK ... "
/home/admin/_cache.sh ramdisk on || exit 1
/home/admin/_cache.sh keyvalue on || exit 1

# *** Wifi, Bluetooth & other RaspberryPi configs ***
if [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian" ]; then

  if [ "${wifi_region}" == "off" ]; then
    echo -e "\n*** DISABLE WIFI ***"
    systemctl disable wpa_supplicant.service
    ifconfig wlan0 down
  fi

  # remove bluetooth services
  systemctl disable bluetooth.service
  systemctl disable hciuart.service

  # remove bluetooth packages
  apt-get remove -y --purge pi-bluetooth bluez bluez-firmware

  # disable audio
  echo -e "\n*** DISABLE AUDIO (snd_bcm2835) ***"
  sed -i "s/^dtparam=audio=on/# dtparam=audio=on/g" ${raspi_configfile}

  # disable DRM VC4 V3D
  echo -e "\n*** DISABLE DRM VC4 V3D driver ***"
  dtoverlay=vc4-fkms-v3d
  sed -i "s/^dtoverlay=${dtoverlay}/# dtoverlay=${dtoverlay}/g" ${raspi_configfile}

  # I2C fix (make sure dtparam=i2c_arm is not on)
  # see: https://github.com/rootzoll/raspiblitz/issues/1058#issuecomment-739517713
  sed -i "s/^dtparam=i2c_arm=.*//g" ${raspi_configfile}
fi

# *** BOOTSTRAP ***
echo -e "\n*** RASPI BOOTSTRAP SERVICE ***"
chmod +x /home/admin/_bootstrap.sh
cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
systemctl enable bootstrap

# *** BACKGROUND TASKS ***
echo -e "\n*** RASPI BACKGROUND SERVICE ***"
chmod +x /home/admin/_background.sh
cp /home/admin/assets/background.service /etc/systemd/system/background.service
systemctl enable background

# *** BACKGROUND SCAN ***
/home/admin/_background.scan.sh install || exit 1

#######
# TOR #
#######
echo
/home/admin/config.scripts/tor.install.sh install || exit 1

###########
# BITCOIN #
###########
echo
/home/admin/config.scripts/bitcoin.install.sh install || exit 1

#######
# I2P #
#######
echo
/home/admin/config.scripts/blitz.i2pd.sh install || exit 1

# *** BLITZ WEB SERVICE ***
echo "Provisioning BLITZ WEB SERVICE"
/home/admin/config.scripts/blitz.web.sh http-on || exit 1

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if ${fatpack}; then
  echo "* FATPACK activated"
  /home/admin/config.scripts/blitz.fatpack.sh || exit 1
else
  echo "* skipping FATPACK"
fi

# check fallback list bitnodes
# update on releases manually in asset folder with:
# curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o ./fallback.bitnodes.nodes
byteSizeList=$(sudo -u admin stat -c %s /home/admin/fallback.bitnodes.nodes)
if [ ${#byteSizeList} -eq 0 ] || [ ${byteSizeList} -lt 10240 ]; then
  echo "Using fallback list from repo: bitnodes"
  rm /home/admin/fallback.bitnodes.nodes 2>/dev/null
  cp /home/admin/assets/fallback.bitnodes.nodes /home/admin/fallback.bitnodes.nodes
fi
chown admin:admin /home/admin/fallback.bitnodes.nodes

# check fallback list bitcoin core
# update on releases manually in asset folder with:
# curl https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/seeds/nodes_main.txt -o ./fallback.bitcoin.nodes
byteSizeList=$(sudo -u admin stat -c %s /home/admin/fallback.bitcoin.nodes)
if [ ${#byteSizeList} -eq 0 ] || [ ${byteSizeList} -lt 10240 ]; then
  echo "Using fallback list from repo: bitcoin core"
  rm /home/admin/fallback.bitcoin.nodes 2>/dev/null
  cp /home/admin/assets/fallback.bitcoin.nodes /home/admin/fallback.bitcoin.nodes
fi
chown admin:admin /home/admin/fallback.bitcoin.nodes

echo
echo "*** raspiblitz.info ***"
cat /home/admin/raspiblitz.info

# *** RASPIBLITZ IMAGE READY INFO ***
echo -e "\n**********************************************"
echo "BASIC SD CARD BUILD DONE"
echo -e "**********************************************\n"
echo "Your SD Card Image for RaspiBlitz is ready (might still do display config)."
echo "Take the chance & look through the output above if you can spot any errors or warnings."
echo -e "\nIMPORTANT IF YOU WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "1. login fresh --> user:admin password:raspiblitz"
echo -e "2. run --> release\n"

# make sure that at least the code is available (also if no internet)
echo "** DISPLAY(${display})"
/home/admin/config.scripts/blitz.display.sh prepare-install || exit 1
# (do last - because it might trigger reboot)
if [ "${display}" != "headless" ] || [ "${baseimage}" = "raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blitz.display.sh set-display ${display}"
  /home/admin/config.scripts/blitz.display.sh set-display ${display} || exit 1
  /home/admin/config.scripts/blitz.display.sh rotate 1 || exit 1
fi

echo "# BUILD DONE - see above"
