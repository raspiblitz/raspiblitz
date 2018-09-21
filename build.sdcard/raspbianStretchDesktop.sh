#!/bin/bash
#########################################################################
# Build your SD card image based on:
# RASPBIAN STRETCH WITH DESKTOP (2018-06-27)
# https://www.raspberrypi.org/downloads/raspbian/
# SHA256: 8636ab9fdd8f58a8ec7dde33b83747696d31711d17ef68267dbbcd6cfb968c24
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script: 
##########################################################################

echo ""
echo "***************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP v0.93*"
echo "***************************************"
echo ""

echo ""
echo "*** RASPI CONFIG ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#raspi-config

# set new default passwort for pi and root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

# set Raspi to boot up automatically with user pi (for the LCD)
# https://www.raspberrypi.org/forums/viewtopic.php?t=21632
sudo raspi-config nonint do_boot_behaviour B2
sudo bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
sudo bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"

# do memory split (16MB)
sudo raspi-config nonint do_memory_split 16

# set to wait until network is available on boot (0 seems to yes)
sudo raspi-config nonint do_boot_wait 0

# autodetect and set your timezone
pip install -U tzupdate
sleep 2
sudo tzupdate

echo ""
echo "*** SOFTWARE UPDATE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#software-update

# installs like on RaspiBolt
sudo apt-get update
sudo apt-get upgrade -f -y --allow-change-held-packages
sudo apt-get install -y htop git curl bash-completion jq dphys-swapfile

# extra: remove some big packages not needed
sudo apt-get remove -y --purge libreoffice*
sudo apt-get clean
sudo apt-get -y autoremove

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
echo "*** HARDENING ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#hardening-your-pi

# fail2ban (no config required)
sudo apt-get install -y fail2ban

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
bitcoinVersion="0.17.0"
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# prepare directories
sudo -u admin mkdir /home/admin/download
cd /home/admin/download

# download resources
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/test.rc4/bitcoin-${bitcoinVersion}rc4-arm-linux-gnueabihf.tar.gz
if [ ! -f "./bitcoin-${bitcoinVersion}rc4-arm-linux-gnueabihf.tar.gz" ]
then
    echo "!!! FAIL !!! Download BITCOIN BINARY not success."
    exit 1
fi
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/test.rc4/SHA256SUMS.asc
if [ ! -f "./SHA256SUMS.asc" ]
then
    echo "!!! FAIL !!! Download SHA256SUMS.asc not success."
    exit 1
fi
sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
if [ ! -f "./laanwj-releases.asc" ]
then
    echo "!!! FAIL !!! Download laanwj-releases.asc not success."
    exit 1
fi

# test checksum
checksum=$(sha256sum --check SHA256SUMS.asc --ignore-missing 2>/dev/null | grep '.tar.gz: OK' -c)
if [ ${checksum} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Bitcoin download checksum not OK"
  exit 1
fi

# check gpg finger print
fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep "${laanwjPGP}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Bitcoin download PGP author not OK"
  exit 1
fi
gpg --import ./laanwj-releases.asc
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

# install
sudo -u admin tar -xvf bitcoin-${bitcoinVersion}rc4-arm-linux-gnueabihf.tar.gz
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-${bitcoinVersion}/bin/*
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
cd /home/admin/download
sudo -u admin wget https://download.litecoin.org/litecoin-${litecoinVersion}/linux/litecoin-${litecoinVersion}-arm-linux-gnueabihf.tar.gz
sudo -u admin tar -xvf litecoin-${litecoinVersion}-arm-linux-gnueabihf.tar.gz
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
#lndVersion="0.5-beta-rc1"
#olaoluwaPGP="65317176B6857F98834EDBE8964EA263DD637C21"
#
# get LND resources
#cd /home/admin/download
#sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/lnd-linux-arm-v${lndVersion}.tar.gz
#sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt
#sudo -u admin wget https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt.sig
#sudo -u admin wget https://keybase.io/roasbeef/pgp_keys.asc
## test checksum
#checksum=$(sha256sum --check manifest-v${lndVersion}.txt --ignore-missing 2>/dev/null | grep '.tar.gz: OK' -c)
#if [ ${checksum} -lt 1 ]; then
#  echo ""
#  echo "!!! BUILD FAILED --> LND download checksum not OK"
#  exit 1
#fi
## check gpg finger print
#fingerprint=$(gpg ./pgp_keys.asc 2>/dev/null | grep "${olaoluwaPGP}" -c)
#if [ ${fingerprint} -lt 1 ]; then
#  echo ""
#  echo "!!! BUILD FAILED --> LND download author PGP not OK"
#  exit 1
#fi
#gpg --import ./pgp_keys.asc
#sleep 2
#verifyResult=$(gpg --verify manifest-v${lndVersion}.txt.sig manifest-v${lndVersion}.txt 2>&1)
#goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
#echo "goodSignature(${goodSignature})"
#correctKey=$(echo ${verifyResult} |  grep "using RSA key ${olaoluwaPGP: -16}" -c)
#echo "correctKey(${correctKey})"
#if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
#  echo ""
#  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signatute(${goodSignature}) verify(${correctKey})"
#    exit 1
#fi
## install
#sudo -u admin tar -xzf lnd-linux-arm-v${lndVersion}.tar.gz
#sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-arm-v${lndVersion}/*
#sleep 3
#installed=$(sudo -u admin lnd --version | grep "${lndVersion}" -c)
#if [ ${installed} -lt 1 ]; then
#  echo ""
#  echo "!!! BUILD FAILED --> Was not able to install LND version(${lndVersion})"
#  exit 1
#fi

##### Build from Source
# To quickly catch up get latest patches if needed
repo="github.com/lightningnetwork/lnd"
commit="25145acc46cc5d18e4e348eed097300b1391d2a7"
# BUILDING LND FROM SOURCE
echo "*** Installing Go ***"
wget https://storage.googleapis.com/golang/go1.10.linux-armv6l.tar.gz
if [ ! -f "./go1.10.linux-armv6l.tar.gz" ]
then
    echo "!!! FAIL !!! Download not success."
    exit 1
fi
sudo tar -C /usr/local -xzf go1.10.linux-armv6l.tar.gz
sudo rm *.gz
sudo mkdir /usr/local/gocode
sudo chmod 777 /usr/local/gocode
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin
export GOPATH=/usr/local/gocode
export PATH=$PATH:$GOPATH/bin
echo "*** Build LND from Source ***"
go get -d $repo
# make sure to always have the same code (commit) to build
# TODO: To update lnd -> change to latest commit
cd $GOPATH/src/$repo
sudo git checkout $commit
make && make install
sudo chmod 555 /usr/local/gocode/bin/lncli
sudo chmod 555 /usr/local/gocode/bin/lnd
sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/admin/.bashrc"
sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/pi/.bashrc"
sudo bash -c "echo 'export PATH=$PATH:/usr/local/gocode/bin/' >> /home/bitcoin/.bashrc"
lndVersionCheck=$(lncli --version)
echo "LND VERSION: ${lndVersionCheck}"
if [ ${#lndVersionCheck} -eq 0 ]; then
  echo "FAIL - Something went wrong with building LND from source."
  echo "Sometimes it may just be a connection issue. Reset to fresh Rasbian and try again?"
  exit 1
fi
echo ""
echo "** Link to /usr/local/bin ***"
sudo ln -s /usr/local/gocode/bin/lncli /usr/local/bin/lncli
sudo ln -s /usr/local/gocode/bin/lnd /usr/local/bin/lnd

echo ""
echo "*** RASPIBLITZ EXTRAS ***"

# for setup schell scripts
sudo apt-get -y install dialog bc

# enable copy of blockchain from 2nd HDD formatted with exFAT
sudo apt-get -y install exfat-fuse

# for blockchain torrent download
sudo apt-get -y install transmission-cli

# for background downloading
sudo apt-get -y install screen

# optimization for torrent download
sudo bash -c "echo 'net.core.rmem_max = 4194304' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.core.wmem_max = 1048576' >> /etc/sysctl.conf"

# *** SHELL SCRIPTS AND ASSETS

# move files from gitclone
cd /home/admin/
sudo -u admin git clone https://github.com/rootzoll/raspiblitz.git
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.sh /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/

# bash aoutstart for admin
sudo bash -c "echo '# automatically start main menu for admin' >> /home/admin/.bashrc"
sudo bash -c "echo './00mainMenu.sh' >> /home/admin/.bashrc"

# bash aoutstart for pi
# run as exec to dont allow easy physical access by keyboard
# see https://github.com/rootzoll/raspiblitz/issues/54
sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/pi/.bashrc'
sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
sudo bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'

# create /home/pi/setup.sh - which will get executed after reboot by autologin pi user
cat > /home/pi/setup.sh <<EOF

# make LCD screen rotation correct
sudo sed --in-place -i "57s/.*/dtoverlay=tft35a:rotate=270/" /boot/config.txt

EOF
sudo chmod +x /home/pi/setup.sh

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
echo "Press ENTER to install LCD and reboot ..."
read key

# give Raspi a default hostname (optional)
sudo raspi-config nonint do_hostname "RaspiBlitz"

# *** RASPIBLITZ / LCD (at last - because makes a reboot) ***
# based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
cd /home/admin/
sudo apt-mark hold raspberrypi-bootloader
git clone https://github.com/goodtft/LCD-show.git
sudo chmod -R 755 LCD-show
sudo chown -R admin:admin LCD-show
cd LCD-show/
sudo ./LCD35-show