#!/bin/sh -eux

echo 'Download the build_sdcard.sh script ...'
wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh
echo 'Build RaspiBlitz ...'
sudo bash build_sdcard.sh -f true -u rootzoll -b dev -d headless -t false -w off -i false
echo 'Add Gnome desktop'
export DEBIAN_FRONTEND=noninteractive
sudo apt install gnome -y
echo 'Deleting SSH pub keys (will be recreated on the first boot) ...'
sudo rm /etc/ssh/ssh_host_*
echo 'OK'
