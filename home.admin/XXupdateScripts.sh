#!/bin/bash
echo ""
echo "*** UPDATING SHELL SCRIPTS FROM GITHUB ***"
echo "justincase, not the final upadte mechanism"
echo "******************************************"
cd /home/admin/raspiblitz
git pull
cd ..
rm *.sh
rm -r assets
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
echo "******************************************"
echo "OK - shell scripts and assests are up to date"
echo "Reboot recommended"
echo ""
