#!/bin/bash

# Just run this script once after a fresh sd card build
# to prepare the image for release as a downloadable sd card image

# raspiblitz.info & logs
echo "deleting raspiblitz info & logs ..."
sudo rm /home/admin/raspiblitz.*
echo "OK"

# SSH Pubkeys (make unique for every sd card image install)
echo "deleting SSH Pub keys ..."
echo "they will get recreated on fresh bootup, by _bootstrap.sh service"
sudo rm /etc/ssh/ssh_host_*
echo "OK"

# https://github.com/rootzoll/raspiblitz/issues/1068#issuecomment-599267503
echo ""
echo "deleting local DNS confs ..."
sudo rm /etc/resolv.conf
echo "OK"

# https://github.com/rootzoll/raspiblitz/issues/1371
echo ""
echo "deleting local WIFI conf ..."
sudo rm /boot/wpa_supplicant.conf 2>/dev/null
echo "OK"

echo " "
echo "Will shutdown now."
echo "Wait until Raspberry LEDs show no activity anymore."
echo "Then remove SD card and make an release image from it."
sudo shutdown now
