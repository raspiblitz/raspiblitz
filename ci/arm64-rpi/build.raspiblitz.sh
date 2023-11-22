#!/bin/sh -eux

echo 'Download the build_sdcard.sh script ...'
wget https://raw.githubusercontent.com/${github_user}/raspiblitz/${branch}/build_sdcard.sh

if [ "${pack}" = "fatpack" ]; then
  fatpack="1"
  # make /dev/shm world writable for qemu
  sudo chmod 777 /dev/shm
else
  fatpack="0"
fi

echo 'Build RaspiBlitz ...'
bash build_sdcard.sh -f ${fatpack} -u ${github_user} -b ${branch} -t false -w off -i false
