#!/bin/bash
#########################################################################
# Build your SD card image based on:
# RASPBIAN STRETCH WITH DESKTOP (2018-11-13)
# https://www.raspberrypi.org/downloads/raspbian/
# SHA256: a121652937ccde1c2583fe77d1caec407f2cd248327df2901e4716649ac9bc97
# 
# or download the image for your ARM based SBC on https://DietPi.com
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script: 
##########################################################################

echo ""
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP v1.00  *"
echo "*****************************************"
echo ""

# 1st optional parameter is the BRANCH to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
echo "*** CHECK INPUT PARAMETERS ***"
wantedBranch="$1"
if [ ${#wantedBranch} -eq 0 ]; then
  wantedBranch="master"
fi
echo "will use code from branch --> '${wantedBranch}'"

# 2nd optional parameter is the GITHUB-USERNAME to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
# if 2nd parameter is used - 1st is mandatory
echo "*** CHECK INPUT PARAMETERS ***"
githubUser="$2"
if [ ${#githubUser} -eq 0 ]; then
  githubUser="rootzoll"
fi
echo "will use code from user --> '${githubUser}'"

sleep 3

echo ""
echo "*** CHECK BASE IMAGE ***"

# armv7=32Bit , armv8=64Bit
echo "Check if Linux ARM based ..." 
isARM=$(uname -m | grep -c 'arm')
if [ ${isARM} -eq 0 ]; then
  echo "!!! FAIL !!!"
  echo "Can just build on ARM Linux, not on:"
  uname -m
  exit 1
fi
echo "OK running on Linux ARM architecture."

# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
echo "Detect Base Image ..." 
baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
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

# fixing locales for build
# https://github.com/rootzoll/raspiblitz/issues/138
# https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
# https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
echo ""
echo "*** FIXING LOCALES FOR BUILD ***"
sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
sudo locale-gen
export LANGUAGE=en_GB.UTF-8
export LANG=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8

# update debian
echo ""
echo "*** UPDATE DEBIAN ***"
sudo apt-get update
sudo apt-get upgrade -f -y --allow-change-held-packages

# special prepare when DietPi
if [ "${baseImage}" = "dietpi" ]; then
  echo ""
  echo "*** PREPARE DietPi ***"
  echo "renaming dietpi user to pi"
  sudo usermod -l pi dietpi
  echo "install pip"
  sudo apt-get update
  sudo apt-get remove -y fail2ban
  sudo apt-get install -y build-essential
  sudo apt-get install -y python-pip
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

fi

# special prepare when Raspbian
if [ "${baseImage}" = "raspbian" ]; then
  echo ""
  echo "*** PREPARE Raspbian ***"
  # do memory split (16MB)
  sudo raspi-config nonint do_memory_split 16
  # set to wait until network is available on boot (0 seems to yes)
  sudo raspi-config nonint do_boot_wait 0
  # set WIFI country so boot does not block
  sudo raspi-config nonint do_wifi_country US
  # extra: remove some big packages not needed
  sudo apt-get remove -y --purge libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi minecraft-pi python-pygame
  sudo apt-get clean
  sudo apt-get -y autoremove
fi

echo ""
echo "*** CONFIG ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#raspi-config

# set new default passwort for root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

# set Raspi to boot up automatically with user pi (for the LCD)
# https://www.raspberrypi.org/forums/viewtopic.php?t=21632
sudo raspi-config nonint do_boot_behaviour B2
sudo bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
sudo bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"

echo ""
echo "*** SOFTWARE UPDATE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#software-update

# installs like on RaspiBolt
sudo apt-get install -y htop git curl bash-completion jq dphys-swapfile

# installs bandwidth monitoring for future statistics
sudo apt-get install -y vnstat

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

echo "*** ADDING SERVICE USER bitcoin"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-the-service-user-bitcoin

# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd

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

echo ""
echo "*** BITCOIN ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md#installation

# set version (change if update is available)
bitcoinVersion="0.17.0.1"

# needed to make sure download is not changed
# calulate with sha256sum and also check with SHA256SUMS.asc
bitcoinSHA256="1b9cdf29a9eada239e26bf4471c432389c2f2784362fc8ef0267ba7f48602292"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# prepare directories
sudo -u admin mkdir /home/admin/download
cd /home/admin/download

# download resources
binaryName="bitcoin-${bitcoinVersion}-arm-linux-gnueabihf.tar.gz"
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
if [ ! -f "./${binaryName}" ]
then
    echo "!!! FAIL !!! Download BITCOIN BINARY not success."
    exit 1
fi

# check binary is was not manipulated (checksum test)
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
  exit 1
fi


# check gpg finger print
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
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signatute(${goodSignature}) verify(${correctKey})"
  exit 1
fi

# correct versions for install if needed
if [ "${bitcoinVersion}" = "0.17.0.1" ]; then 
 bitcoinVersion="0.17.0"
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

echo ""
echo "*** LITECOIN ***"
# based on https://medium.com/@jason.hcwong/litecoin-lightning-with-raspberry-pi-3-c3b931a82347

# set version (change if update is available)
litecoinVersion="0.16.3"
litecoinSHA256="fc6897265594985c1d09978b377d51a01cc13ee144820ddc59fbb7078f122f99"
cd /home/admin/download

# download
binaryName="litecoin-${litecoinVersion}-arm-linux-gnueabihf.tar.gz"
sudo -u admin wget https://download.litecoin.org/litecoin-${litecoinVersion}/linux/${binaryName}

# check download
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${litecoinSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LITECOIN BINARY not matching SHA256 checksum: ${litecoinSHA256}"
  exit 1
fi

# install
sudo -u admin tar -xvf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin litecoin-${litecoinVersion}/bin/*
installed=$(sudo -u admin litecoind --version | grep "${litecoinVersion}" -c)
if [ ${installed} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install litecoind version(${litecoinVersion})"
  exit 1
fi

echo ""
echo "*** LND ***"

## based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_40_lnd.md#lightning-lnd
lndVersion="0.5.2-beta"
lndSHA256="9adf9f3d0b8a62942f68d75ffe043f9255319209f751dee4eac82375ec0a86cd"
olaoluwaPGP="BD599672C804AF2770869A048B80CD2BB8BD8132"

# get LND resources
cd /home/admin/download
binaryName="lnd-linux-armv7-v${lndVersion}.tar.gz"
sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}
sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt
sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt.sig
sudo -u admin wget https://keybase.io/roasbeef/pgp_keys.asc

# check binary is was not manipulated (checksum test)
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum: ${lndSHA256}"
  exit 1
fi

# check gpg finger print
gpg ./pgp_keys.asc
fingerprint=$(gpg ./pgp_keys.asc 2>/dev/null | grep "${olaoluwaPGP}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> Bitcoin PGP author not as expected"
  echo "Should contain olaoluwaPGP: ${olaoluwaPGP}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc
sleep 3
verifyResult=$(gpg --verify manifest-v${lndVersion}.txt.sig 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${olaoluwaPGP}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signatute(${goodSignature}) verify(${correctKey})"
  exit 1
fi

# install
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-armv7-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi

# Go is needed for ZAP connect later
echo "*** Installing Go ***"
wget https://storage.googleapis.com/golang/go1.11.linux-armv6l.tar.gz
if [ ! -f "./go1.11.linux-armv6l.tar.gz" ]
then
    echo "!!! FAIL !!! Download not success."
    exit 1
fi
sudo tar -C /usr/local -xzf go1.11.linux-armv6l.tar.gz
sudo rm *.gz
sudo mkdir /usr/local/gocode
sudo chmod 777 /usr/local/gocode
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin
export GOPATH=/usr/local/gocode
export PATH=$PATH:$GOPATH/bin
echo ""

##### Build from Source
## To quickly catch up get latest patches if needed
#repo="github.com/lightningnetwork/lnd"
#commit="3f57f65bf0cb710159b0182391d1d75e9e3005bc"
## BUILDING LND FROM SOURCE
#echo "*** Installing Go ***"
#wget https://storage.googleapis.com/golang/go1.11.linux-armv6l.tar.gz
#if [ ! -f "./go1.11.linux-armv6l.tar.gz" ]
#then
#    echo "!!! FAIL !!! Download not success."
#    exit 1
#fi
#sudo tar -C /usr/local -xzf go1.11.linux-armv6l.tar.gz
#sudo rm *.gz
#sudo mkdir /usr/local/gocode
#sudo chmod 777 /usr/local/gocode
#export GOROOT=/usr/local/go
#export PATH=$PATH:$GOROOT/bin
#export GOPATH=/usr/local/gocode
#export PATH=$PATH:$GOPATH/bin
#echo ""
#echo "*** Build LND from Source ***"
#go get -d $repo
## make sure to always have the same code (commit) to build
## TODO: To update lnd -> change to latest commit
#cd $GOPATH/src/$repo
#sudo git checkout $commit
#make && make install
#sudo chmod 555 /usr/local/gocode/bin/lncli
#sudo chmod 555 /usr/local/gocode/bin/lnd
#sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/admin/.bashrc"
#sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/pi/.bashrc"
#sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/bitcoin/.bashrc"
#lndVersionCheck=$(lncli --version)
#echo "LND VERSION: ${lndVersionCheck}"
#if [ ${#lndVersionCheck} -eq 0 ]; then
#  echo "FAIL - Something went wrong with building LND from source."
#  echo "Sometimes it may just be a connection issue. Reset to fresh Rasbian and try again?"
#  exit 1
#fi
#echo ""
#echo "** Link to /usr/local/bin ***"
#sudo ln -s /usr/local/gocode/bin/lncli /usr/local/bin/lncli
#sudo ln -s /usr/local/gocode/bin/lnd /usr/local/bin/lnd

echo ""
echo "*** RASPIBLITZ EXTRAS ***"

# for setup schell scripts
sudo apt-get -y install dialog bc

# enable copy of blockchain from 2nd HDD formatted with exFAT
sudo apt-get -y install exfat-fuse

# for blockchain torrent download
sudo apt-get -y install transmission-cli
sudo apt-get -y install rtorrent

# for background downloading
sudo apt-get -y install screen

# optimization for torrent download
sudo bash -c "echo 'net.core.rmem_max = 4194304' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.core.wmem_max = 1048576' >> /etc/sysctl.conf"

# *** SHELL SCRIPTS AND ASSETS

# move files from gitclone
cd /home/admin/
sudo -u admin git clone -b ${wantedBranch} https://github.com/${githubUser}/raspiblitz.git
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh

# add /sbin to path for all
sudo bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

# profile path for admin
sudo bash -c "echo '' >> /home/admin/.profile"
sudo bash -c "echo 'GOROOT=/usr/local/go' >> /home/admin/.profile"
sudo bash -c "echo 'PATH=\$PATH:\$GOROOT/bin' >> /home/admin/.profile"
sudo bash -c "echo 'GOPATH=/usr/local/gocode' >> /home/admin/.profile"
sudo bash -c "echo 'PATH=\$PATH:\$GOPATH/bin' >> /home/admin/.profile"

# bash autostart for admin
sudo bash -c "echo '# shortcut commands' >> /home/admin/.bashrc"
sudo bash -c "echo 'source /home/admin/_commands.sh' >> /home/admin/.bashrc"
sudo bash -c "echo '# automatically start main menu for admin' >> /home/admin/.bashrc"
sudo bash -c "echo './00mainMenu.sh' >> /home/admin/.bashrc"

# bash autostart for pi
# run as exec to dont allow easy physical access by keyboard
# see https://github.com/rootzoll/raspiblitz/issues/54
sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/pi/.bashrc'
sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
sudo bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'

# create /home/admin/setup.sh - which will get executed after reboot by autologin pi user
cat > /home/admin/setup.sh <<EOF

# make LCD screen rotation correct
sudo sed --in-place -i "57s/.*/dtoverlay=tft35a:rotate=270/" /boot/config.txt

EOF
sudo chmod +x /home/admin/setup.sh

echo ""
echo "*** HARDENING ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#hardening-your-pi

# fail2ban (no config required)
sudo apt-get install -y fail2ban

# *** BOOTSTRAP ***
# see background README for details
echo ""
echo "*** RASPI BOOSTRAP SERVICE ***"
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
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "If you see fails above .. please run again later on:"
echo "sudo /home/admin/config.scripts/internet.tor.sh prepare"
echo ""

# *** RASPIBLITZ IMAGE READY ***
echo ""
echo "**********************************************"
echo "ALMOST READY"
echo "**********************************************"
echo ""
echo "Your SD Card Image for RaspiBlitz is almost ready."
echo "Last step is to install LCD drivers. This will reboot your Pi when done."
echo ""
echo "Maybe take the chance and look thru the output above if you can spot any errror."
echo ""
echo "After final reboot - your SD Card Image is ready."
echo ""
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "login once after reboot without HDD and run 'XXprepareRelease.sh'"
echo ""
echo "to continue reboot with sudo shutdown -r  now and login with admin"

# install LCD only on an rPI running Raspbian
if [ "${baseImage}" = "raspbian" ]; then
  echo "Press ENTER to install LCD and reboot ..."
  read key

  # give Raspi a default hostname (optional)
  sudo raspi-config nonint do_hostname "RaspiBlitz"

  # *** Display selection ***
  dialog --title "Display" --yesno "Are you using the default display available from Amazon?\nSelect 'No' if you are using the Swiss version from play-zone.ch!" 6 80
  defaultDisplay=$?

  if [ "${defaultDisplay}" = "0" ]; then

    # *** RASPIBLITZ / LCD (at last - because makes a reboot) ***
    # based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
    
    echo "--> LCD DEFAULT"
    cd /home/admin/
    sudo apt-mark hold raspberrypi-bootloader
    git clone https://github.com/goodtft/LCD-show.git
    sudo chmod -R 755 LCD-show
    sudo chown -R admin:admin LCD-show
    cd LCD-show/
    sudo ./LCD35-show

  else

    # Download and install the driver
    # based on http://www.raspberrypiwiki.com/index.php/3.5_inch_TFT_800x480@60fps

    echo "--> LCD ALTERNATIVE"
    cd /boot
    sudo wget http://www.raspberrypiwiki.com/download/RPI-HD-35-INCH-TFT/dt-blob-For-3B-plus.bin
    sudo mv dt-blob-For-3B-plus.bin dt-blob.bin
    cat <<EOF >> config.txt

  dtparam=spi=off
  dtparam=i2c_arm=off

  # Set screen size and any overscan required
  overscan_left=0
  overscan_right=0
  overscan_top=0
  overscan_bottom=0
  framebuffer_width=800
  framebuffer_height=480


  enable_dpi_lcd=1
  display_default_lcd=1
  dpi_group=2
  dpi_mode=87
  dpi_output_format=0x6f015

  # set up the size to 800x480
  hdmi_timings=480 0 16 16 24 800 0 4 2 2 0 0 0 60 0 32000000 6

  #rotate screen
  display_rotate=3

  dtoverlay=i2c-gpio,i2c_gpio_scl=24,i2c_gpio_sda=23
  fi
EOF
    init 6
  fi
fi
