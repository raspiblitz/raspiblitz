#!/bin/bash

########################################
# AFTER FINAL SETUP TASKS
echo "# AFTER FINAL SETUP TASKS" >> /home/admin/raspiblitz.log
echo "# /home/admin/_provision.xfinal.sh" > /var/cache/raspiblitz/final.log

# signal that setup phase is over
/home/admin/_cache.sh set setupPhase "done"

# source info fresh
source /home/admin/raspiblitz.info
echo "# source /home/admin/raspiblitz.info" >> /home/admin/raspiblitz.log
cat /home/admin/raspiblitz.info >> /home/admin/raspiblitz.log

# make sure for future starts that blockchain service gets started after bootstrap
# so deamon reloas needed ... system will go into reboot after last loop
# needs to be after wait loop because otherwise the "restart" on COPY OVER LAN will not work
echo "# Updating service bitcoind.service ..." >> /home/admin/raspiblitz.log
sudo sed -i "s/^Wants=.*/Wants=bootstrap.service/g" /etc/systemd/system/bitcoind.service
sudo sed -i "s/^After=.*/After=bootstrap.service/g" /etc/systemd/system/bitcoind.service
sudo systemctl daemon-reload 2>/dev/null

# delete setup data from RAM
echo "# removing raspiblitz.setup" >> /home/admin/raspiblitz.log
sudo rm /var/cache/raspiblitz/temp/raspiblitz.setup

########################################
# AFTER SETUP REBOOT
# touchscreen activation, start with configured SWAP, fix LCD text bug
echo "# SHUTTING DOWN ..." >> /home/admin/raspiblitz.log
sudo cp /home/admin/raspiblitz.log /home/admin/raspiblitz.setup.log
sudo chmod 640 /home/admin/raspiblitz.setup.log
sudo chown root:sudo /home/admin/raspiblitz.setup.log
timeout 120 sudo /home/admin/config.scripts/blitz.shutdown.sh reboot finalsetup
# if system has not rebooted yet - force reboot directly
sudo shutdown -r now