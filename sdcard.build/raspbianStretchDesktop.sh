#########################################################################
# Build your SD card image based on:
# RASPBIAN STRETCH WITH DESKTOP (2018-06-27)
# https://www.raspberrypi.org/downloads/raspbian/
# SHA256: 8636ab9fdd8f58a8ec7dde33b83747696d31711d17ef68267dbbcd6cfb968c24
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script
##########################################################################

# *** RASPI CONFIG ***
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#raspi-config

# A) Set Raspi to boot up automatically with user pi (for the LCD)
# https://www.raspberrypi.org/forums/viewtopic.php?t=21632
sudo raspi-config nonint do_boot_behaviour B2

# B) Give Raspi a default hostname (optional)
sudo raspi-config nonint do_hostname "RaspiBlitz"

# do memory split (16MB)
# TODO: sudo raspi-config nonint do_memory_split %d

# *** SOFTWARE UPDATE ***
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#software-update

sudo apt-get update
sudo apt-get upgrade
sudo apt-get install htop git curl bash-completion jq dphys-swapfile

# *** ADDING MAIN USER "admin" ***
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-main-user-admin
# using the default password 'raspiblitz'

# TODO: set password automatically
sudo adduser admin
sudo adduser admin sudo
sudo chsh admin -s /bin/bash
sudo passwd root

# TODO
# $ sudo visudo
# %sudo  ALL=(ALL:ALL) ALL
# %sudo   ALL=(ALL) NOPASSWD:ALL

# *** ADDING SERVICE USER “bitcoin”
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-the-service-user-bitcoin

sudo adduser bitcoin

# *** SWAP FILE ***
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#moving-the-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

# --> CONTINUE: https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#hardening-your-pi

# *** TODOS / DECIDE / GIVE MANUAL INTRUCTIONS ******

# ???
# sudo raspi-config nonint do_ssh %d

# Wait for network at boot?
# sudo raspi-config nonint get_boot_wait
# sudo raspi-config nonint do_boot_wait %d

# automaticall detect and set time zone?
# maybe do on in setup scripts

