#!/bin/bash
#########################################################################
# Build your SD card image based on:
# Raspbian Buster Desktop (2020-05-27)
# https://www.raspberrypi.org/downloads/raspbian/
# SHA256: b9a5c5321b3145e605b3bcd297ca9ffc350ecb1844880afd8fb75a7589b7bd04
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script:
##########################################################################

echo ""
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP v1.6   *"
echo "*****************************************"
echo ""

# 1st optional parameter is the BRANCH to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
echo "*** CHECK INPUT PARAMETERS ***"
wantedBranch="$1"
if [ ${#wantedBranch} -eq 0 ]; then
  wantedBranch="master"
else
  if [ "${wantedBranch}" == "-h" -o "${wantedBranch}" == "--help" ]; then
     echo "Usage: [branch] [github user] [root partition] [LCD screen installed true|false] [Wifi disabled true|false]"
     echo "Example (USB boot, no LCD and no wifi): $0 v1.6 rootzoll /dev/sdb2 false true"
     exit 1
  fi
fi
echo "will use code from branch --> '${wantedBranch}'"

# 2nd optional parameter is the GITHUB-USERNAME to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
# if 2nd parameter is used - 1st is mandatory
githubUser="$2"
if [ ${#githubUser} -eq 0 ]; then
  githubUser="rootzoll"
fi
echo "will use code from user --> '${githubUser}'"

# 3rd optional parameter is the root partition
rootPartition="$3"
if [ ${#rootPartition} -eq 0 ]; then
  rootPartition="/dev/mmcblk0p2"
fi
echo "will use root partition --> '${rootPartition}'"

# 4th optional parameter is the LCD screen
lcdInstalled="$4"
if [ ${#lcdInstalled} -eq 0 ]; then
  lcdInstalled="true"
else
  if [ "${lcdInstalled}" != "false" ]; then
     lcdInstalled="true"
  fi
fi
echo "will activate LCD screen --> '${lcdInstalled}'"

# 5th optional parameter is Wifi
disableWifi="$5"
if [ ${#disableWifi} -eq 0 ]; then
  disableWifi="false"
else
  if [ "${disableWifi}" != "true" ]; then
     disableWifi="false"
  fi
fi
echo "will disable wifi --> '${disableWifi}'"

# 6th optional parameter is Wifi country
wifiCountry="$6"
if [ ${#wifiCountry} -eq 0 ]; then
  wifiCountry="US"
fi
if [ "${disableWifi}" == "false" ]; then
   echo "will use Wifi country --> '${wifiCountry}'"
fi

echo -n "Do you wish to install Raspiblitz branch ${wantedBranch}? (yes/no) "
read installRaspiblitzAnswer
if [ "$installRaspiblitzAnswer" == "yes" ] ;then
   echo ""
   echo ""
else
   exit 1
fi


echo "Installing Raspiblitz..."

sleep 3

echo ""
echo "*** CHECK BASE IMAGE ***"

echo "Detect CPU architecture ..."
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
  uname -m
  exit 1
else
  echo "OK running on $(uname -m) architecture."
fi

# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
echo "Detect Base Image ..."
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
  if [ $(uname -n | grep -c 'raspberrypi') -eq 0 ]; then
    baseImage="armbian"
  else
    baseImage="raspbian64"
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
  echo "!!! FAIL !!!"
  echo "Base Image cannot be detected or is not supported."
  exit 1
else
  echo "OK running ${baseImage}"
fi

if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "dietpi" ] ; then
  # fixing locales for build
  # https://github.com/rootzoll/raspiblitz/issues/138
  # https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
  # https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
  echo ""
  echo "*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=en_US.UTF-8
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8

  # https://github.com/rootzoll/raspiblitz/issues/684
  sudo sed -i "s/^    SendEnv LANG LC.*/#   SendEnv LANG LC_*/g" /etc/ssh/ssh_config

  # remove unneccesary files
  sudo rm -rf /home/pi/MagPi
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

# special prepare when DietPi
if [ "${baseImage}" = "dietpi" ]; then
  echo "renaming dietpi user to pi"
  sudo usermod -l pi dietpi
fi

# special prepare when Raspbian
if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspbian64" ]; then
  # do memory split (16MB)
  sudo raspi-config nonint do_memory_split 16
  # set to wait until network is available on boot (0 seems to yes)
  sudo raspi-config nonint do_boot_wait 0
  # set WIFI country so boot does not block
  if [ "${disableWifi}" == "false" ]; then
     sudo raspi-config nonint do_wifi_country $wifiCountry
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
  # use command to check last fsck check: sudo tune2fs -l ${rootPartition}
  sudo tune2fs -c 1 ${rootPartition}
  # see https://github.com/rootzoll/raspiblitz/issues/1053#issuecomment-600878695

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

# special prepare when Ubuntu or Armbian
if [ "${baseImage}" = "ubuntu" ] || [ "${baseImage}" = "armbian" ]; then
  # make user pi and add to sudo
  sudo adduser --disabled-password --gecos "" pi
  sudo adduser pi sudo
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

if [ "${lcdInstalled}" == "true" ]; then
   if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspbian64" ]; then
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
sudo apt install -y btrfs-progs btrfs-tools

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
# install killall, fuser
sudo apt install -y psmisc

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

# "*** BITCOIN ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md#installation

echo ""
echo "*** PREPARING BITCOIN & Co ***"

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="0.20.0"

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
gpg ./laanwj-releases.asc
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
downloadOK=0
binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
if [ ! -f "./${binaryName}" ]; then
   sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
fi
if [ ! -f "./${binaryName}" ]; then
   echo "!!! FAIL !!! Download BITCOIN BINARY not success."
else
   # check binary checksum test
   binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
   if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
      echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
      rm -v ./${binaryName}
   else
      downloadOK=1
   fi
fi
if [ downloadOK == 0 ]; then
    exit 1
fi

echo ""
echo "****************************************"
echo "OK --> VERIFIED BITCOIN CHECKSUM CORRECT"
echo "****************************************"
echo ""

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

# "*** LND ***"
## based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_40_lnd.md#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
lndVersion="0.11.1-beta"

# olaoluwa
#PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
#PGPcheck="9769140D255C759B1EB77B46A96387A57CAAE94D"
# bitconner
PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"
# Joost Jager
#PGPpkeys="https://keybase.io/joostjager/pgp_keys.asc"
#PGPcheck="D146D0F68939436268FA9A130E26BB61B76C4D3A"

# get LND resources
cd /home/admin/download

# download lnd binary checksum manifest
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt

# check if checksums are signed by lnd dev team
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt.sig
sudo -u admin wget --no-check-certificate -N -O "pgp_keys.asc" ${PGPpkeys}
gpg ./pgp_keys.asc
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
verifyResult=$(gpg --verify manifest-v${lndVersion}.txt.sig 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
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
   sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}
fi

# check binary was not manipulated (checksum test)
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum: ${lndSHA256}"
  rm -v ./${binaryName}
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> VERIFIED LND CHECKSUM IS CORRECT"
  echo "****************************************"
  echo ""
fi

# install
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi
sudo chown -R admin /home/admin

echo "*** Python DEFAULT libs & dependencies ***"

# for setup schell scripts
sudo apt -y install dialog bc python3-dialog

# libs (for global python scripts)
sudo -H python3 -m pip install grpcio==1.29.0
sudo -H python3 -m pip install googleapis-common-protos==1.51.0
sudo -H python3 -m pip install toml==0.10.1
sudo -H python3 -m pip install j2cli==0.3.10
sudo -H python3 -m pip install requests[socks]==2.21.0

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

# *** SHELL SCRIPTS AND ASSETS

# move files from gitclone
cd /home/admin/
sudo -u admin rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b ${wantedBranch} https://github.com/${githubUser}/raspiblitz.git
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
 
if [ "${lcdInstalled}" == "true" ]; then
  if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspbian64" ] || \
  [ "${baseImage}" = "armbian" ] || [ "${baseImage}" = "ubuntu" ] ; then
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
fi

echo ""
echo "*** HARDENING ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_21_security.html

# fail2ban (no config required)
sudo apt install -y --no-install-recommends python3-systemd fail2ban 

if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspbian64" ]; then
  if [ "${disableWifi}" == "true" ]; then
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
fi

# *** CACHE DISK IN RAM ***
echo "Activating CACHE RAM DISK ... "
sudo /home/admin/config.scripts/blitz.cache.sh on

# *** BOOTSTRAP ***
# see background README for details
echo ""
echo "*** RASPI BOOTSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp ./assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND ***
echo ""
echo "*** RASPI BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp ./assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

# *** TOR Prepare ***
echo "*** Prepare TOR source+keys ***"
sudo /home/admin/config.scripts/internet.tor.sh prepare
echo ""

# *** RASPIBLITZ LCD DRIVER (do last - because makes a reboot) ***
# based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
if [ "${lcdInstalled}" == "true" ]; then
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
  elif [ "${baseImage}" = "raspbian64" ]; then
    echo "*** 64bit LCD DRIVER ***"
    echo "--> Downloading LCD Driver from Github"
    cd /home/admin/
    sudo -u admin git clone https://github.com/tux1c/wavesharelcd-64bit-rpi.git
    sudo -u admin chmod -R 755 wavesharelcd-64bit-rpi
    sudo -u admin chown -R admin:admin wavesharelcd-64bit-rpi
    cd wavesharelcd-64bit-rpi
    sudo -u admin git reset --hard 5a206a7 || exit 1
    # TODO touchscreen calibration
    # https://github.com/tux1c/wavesharelcd-64bit-rpi#adapting-guide-to-other-lcds
  fi
fi


# *** RASPIBLITZ IMAGE READY ***
echo ""
echo "**********************************************"
echo "SD CARD BUILD DONE"
echo "**********************************************"
echo ""

if [ "${lcdInstalled}" == "true" ]; then
   echo "Your SD Card Image for RaspiBlitz is almost ready."
   if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "raspbian64" ]; then
      echo "Last step is to install LCD drivers. This will reboot your Pi when done."
      echo ""
   fi
else
   echo "Your SD Card Image for RaspiBlitz is ready."
fi
echo "Take the chance & look thru the output above if you can spot any errror."
echo ""
if [ "${lcdInstalled}" == "true" ]; then
   echo "After final reboot - your SD Card Image is ready."
   echo ""
fi
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "login once after reboot without external HDD/SSD and run 'XXprepareRelease.sh'"
echo "REMEMBER for login now use --> user:admin password:raspiblitz"
echo ""

if [ "${lcdInstalled}" == "true" ]; then
  # activate LCD and trigger reboot
  # dont do this on dietpi to allow for automatic build
  if [ "${baseImage}" = "raspbian" ]; then
    sudo chmod +x -R /home/admin/LCD-show
    cd /home/admin/LCD-show/
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./LCD35-show
  elif [ "${baseImage}" = "raspbian64" ]; then
    cd /home/admin/wavesharelcd-64bit-rpi
    # from https://github.com/tux1c/wavesharelcd-64bit-rpi/blob/master/install.sh
    # prepare X11
    rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
    mkdir -p /etc/X11/xorg.conf.d
    cp -rf ./99-calibration.conf  /etc/X11/xorg.conf.d/99-calibration.conf
    cp -rf ./99-fbturbo.conf  /etc/X11/xorg.conf.d/99-fbturbo.conf

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
    apt-get install xserver-xorg-input-evdev
    cp -rf /usr/share/X11/xorg.conf.d/10-evdev.conf /usr/share/X11/xorg.conf.d/45-evdev.conf

    echo "reboot now"
    reboot

  else
    echo "Use 'sudo reboot' to restart manually."
  fi
fi
