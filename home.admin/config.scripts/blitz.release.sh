#!/bin/bash

# Just run this script once after a fresh sd card build
# to prepare the image for release as a downloadable sd card image
# call with parameter `-quick` to skip skip os update

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})"

# write release info to to version file
echo "writing codeRelease commit ro version file:"
releaseCommit=$(git -C /home/admin/raspiblitz rev-parse --short HEAD)
sed -i "s/^codeRelease=\".*\"/codeRelease=\"${releaseCommit}\"/" /home/admin/_version.info
cat /home/admin/_version.info
echo

# stop background services
sudo systemctl stop background.service
sudo systemctl stop background.scan.service

# remove stop flag (if exists)
echo "deleting stop flag .."
sudo rm ${raspi_bootdir}/stop 2>/dev/null

# cleaning logs
echo "deleting raspiblitz & system logs .."
sudo rm -rf /var/log/journal/* 2>/dev/null
sudo rm /var/log/redis/* 2>/dev/null
sudo rm /var/log/private/* 2>/dev/null
sudo rm /var/log/nginx/* 2>/dev/null
sudo rm /home/admin/*.log 2>/dev/null
logger -p info "****** RASPIBLITZ RELEASE ******"
echo "OK"

# clean raspiblitz.info toward the values set by sd card build script
echo "cleaning raspiblitz.info"
source /home/admin/raspiblitz.info
echo "baseimage=${baseimage}" > /home/admin/raspiblitz.info
echo "cpu=${cpu}" >> /home/admin/raspiblitz.info
echo "blitzapi=${blitzapi}" >> /home/admin/raspiblitz.info
echo "displayClass=${displayClass}" >> /home/admin/raspiblitz.info

# https://github.com/rootzoll/raspiblitz/issues/1371
echo
echo "deactivate local WIFI ..."
sudo nmcli radio wifi off
echo "OK"

# make sure that every install runs API with own secret
# https://github.com/raspiblitz/raspiblitz/issues/4469
echo
echo "deleting old API conf ..."
sudo rm /home/blitzapi/blitz_api/.env 2>/dev/null
REDIS_ENABLED=$(sudo systemctl is-enabled redis 2>/dev/null | grep -c enabled)
if [ ${REDIS_ENABLED} -gt 0 ]; then
    echo "disable redis for initial start ..."
    sudo systemctl stop redis 2>/dev/null
    sudo systemctl disable redis 2>/dev/null
fi
echo "deleting redis data (if still there) ..."
sudo rm /var/lib/redis/dump.rdb 2>/dev/null
echo "OK"

# https://github.com/rootzoll/raspiblitz/issues/1068#issuecomment-599267503
echo
echo "reset DNS confs ..."
echo -e "nameserver 1.1.1.1\nnameserver 84.200.69.80" | sudo tee /etc/resolv.conf > /dev/null
echo "OK"

# make sure Tor respo signing keys are uptodate #4648
wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/torproject.gpg >/dev/null

# update system (only security updates with minimal risk of breaking changes)
if [ "$1" != "-quick" ]; then
  echo
  echo "update OS ..."
  sudo apt-get update -y
  sudo apt-get upgrade -o Dir::Etc::SourceList=/etc/apt/sources.list.d/security.list -y
  sudo apt-get upgrade openssh-server -y
  sudo dpkg --configure -a
else
  echo
  echo "skipping OS update ..."
fi

# SSH Pubkeys (make unique for every sd card image install)
echo
echo "deleting SSH Pub keys ..."
echo "keys will get recreated and sshd reactivated on fresh bootup, by _bootstrap.sh service"
sudo systemctl stop ssh
sudo systemctl disable ssh
sudo rm /etc/ssh/ssh_host_*
echo "OK"

# force locale - see #4861
# next major release should make sure to be set during sd build card
echo
echo "Forcing locales ..."
sudo sed -i '/^en_US.UTF-8/s/^#//' /etc/locale.gen
sudo sed -i '/^en_GB.UTF-8/s/^/#/' /etc/locale.gen
sudo locale-gen
echo -e "LANG=en_US.UTF-8\nLANGUAGE=en_US.UTF-8\nLC_ALL=en_US.UTF-8" | sudo tee /etc/default/locale > /dev/null

# make sure file system is clean and ready for release
echo
echo "fsck on first boot ..."
sudo touch /forcefsck
if [ -e /dev/mmcblk0 ]; then
  echo "fsck on /dev/mmcblk0 ..."
  sudo umount /dev/mmcblk0p1
  sudo fsck -fy /dev/mmcblk0p1
fi

echo
echo "Will shutdown now."
echo "Wait until Raspberry LEDs show no activity anymore."
echo "Then remove SD card and make an release image from it."
sudo shutdown now
