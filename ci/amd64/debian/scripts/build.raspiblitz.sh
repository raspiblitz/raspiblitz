#!/bin/sh -eux

echo 'Download the build_sdcard.sh script ...'
wget https://raw.githubusercontent.com/${github_user}/raspiblitz/${branch}/build_sdcard.sh

if [ ${pack} = "fatpack" ]; then
  fatpack="1"
else
  fatpack="0"
fi

if [ "${desktop}" = "gnome" ]; then
  echo 'Add Gnome desktop'
  export DEBIAN_FRONTEND=none
  sudo apt install gnome -y
fi

echo 'Build RaspiBlitz ...'
bash build_sdcard.sh -f ${fatpack} -u ${github_user} -b ${branch} -d headless -t false -w off -i false
