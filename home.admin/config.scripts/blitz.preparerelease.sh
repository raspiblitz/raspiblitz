#!/bin/bash

# Just run this script once after a fresh sd card build
# to prepare the image for release as a downloadable sd card image

# cleaning logs
echo "deleting raspiblitz & system logs .."
sudo rm /var/log/* 2>/dev/null
sudo rm /var/log/redis/* 2>/dev/null
sudo rm /var/log/private/* 2>/dev/null
sudo rm /var/log/nginx/* 2>/dev/null
sudo rm /home/admin/*.log 2>/dev/null
echo "OK"

# clean raspiblitz.info toward the values set by sd card build script
echo "cleaning raspiblitz.info"
source /home/admin/raspiblitz.info
echo "baseimage=${baseimage}" > /home/admin/raspiblitz.info
echo "cpu=${cpu}" >> /home/admin/raspiblitz.info
echo "blitzapi=${blitzapi}" >> /home/admin/raspiblitz.info
echo "displayClass=${displayClass}" >> /home/admin/raspiblitz.info

# SSH Pubkeys (make unique for every sd card image install)
echo
echo "deleting SSH Pub keys ..."
echo "they will get recreated on fresh bootup, by _bootstrap.sh service"
sudo rm /etc/ssh/ssh_host_*
echo "OK"

# https://github.com/rootzoll/raspiblitz/issues/1068#issuecomment-599267503
echo
echo "deleting local DNS confs ..."
sudo rm /etc/resolv.conf
echo "OK"

# make sure that every install runs API with own secret=
echo
echo "deleting old API conf ..."
sudo rm /home/blitzapi/blitz_api/.env 2>/dev/null
echo "OK"

# https://github.com/rootzoll/raspiblitz/issues/1371
echo
echo "deleting local WIFI conf ..."
sudo rm /boot/wpa_supplicant.conf 2>/dev/null
# reset entries
echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US" | sudo tee /etc/wpa_supplicant/wpa_supplicant.conf  2>/dev/null
echo "OK"

echo "shutdown redis ..."
sudo systemctl stop redis
sleep 3

echo
echo "Will shutdown now."
echo "Wait until Raspberry LEDs show no activity anymore."
echo "Then remove SD card and make an release image from it."
sudo shutdown now
