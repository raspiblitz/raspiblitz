#!/bin/bash
echo ""
echo "*** UPDATING SHELL SCRIPTS FROM GITHUB ***"
echo "******************************************"
cd /home/admin/raspiblitz
get_latest_release_tag() {
  curl --silent "https://api.github.com/repos/charlesrocket/raspiblitz/releases/latest" |
    grep '"tag_name":' |
    sed -E 's/.*"([^"]+)".*/\1/'
}
vTAG=`get_latest_release_tag`
wget https://github.com/charlesrocket/raspiblitz/archive/$vTAG.zip
unzip $vTAG.zip
cd ..
rm *.sh
rm -r assets
sudo -u admin cp /home/admin/raspiblitz/raspiblitz-$vTAG/home.admin/*.sh /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
echo "******************************************"
echo "OK - shell scripts and assests are up to date"
echo "Reboot recommended"
echo ""
