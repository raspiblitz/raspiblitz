#!/bin/sh -eux

echo 'Download the blitz.fatpack.sh script ...'
wget https://raw.githubusercontent.com/${github_user}/raspiblitz/${branch}/home.admin/config.scripts/blitz.fatpack.sh

# make /dev/shm world writable for qemu
sudo chmod 777 /dev/shm

echo 'Build Fatpack ...'
bash blitz.fatpack.sh
