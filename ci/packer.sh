#!/usr/bin/env bash

#########################################################################
# script to trigger packer image build on a debian LIVE system
# see FAQ.dev.md for instructions
##########################################################################

# YOUR REPO (REPLACE WITH YOUR OWN FORK IF NEEDED)
REPO="https://github.com/raspiblitz/raspiblitz"

# folders to store the build results
BUILDFOLDER="images"

echo "Build RaspiBlitz install images on a Debian LIVE system"
echo "From repo (change in script is needed):"
echo $REPO
echo "Results will be stored in:"
echo $BUILDFOLDER

# give info if not started with parameters
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Start this script in the root of an writable 128GB NTFS formatted USB drive:"
  echo "packer.sh [BRANCH] [lean|fat|x86]"
  exit 1
fi

BRANCH=$1
OUTPUT=$2

# check if branch is set
if [ "$BRANCH" == "[BRANCH]" ]; then
  echo "error='branch not set'"
  exit 1
fi

# check if output is set
if [ -z "$OUTPUT" ]; then
  echo "error='output not set'"
  exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root / may use sudo'"
  exit 1
fi

# install git and make
apt update && apt install -y git make

# clean old repo
rm -rf raspiblitz 2>/dev/null

# download the repo
git clone $REPO
if [ $? -gt 0 ]; then
  echo "# REPO: ${REPO}"
  echo "error='git clone failed'"
  exit 1
fi

cd raspiblitz

# checkout the desired branch
git checkout $BRANCH

# get code version
codeVersion=$(cat ./home_admin/_version.info | grep 'codeVersion="' | cut -d'"' -f2)
if [ ${#codeVersion} -eq 0 ]; then
  echo "error='codeVersion not found'"
  exit 1
fi
echo "# RaspiBlitz Version: ${codeVersion}"

# get date as string fromatted like YEAR-MONTH-DAY
dateString=$(date +%Y-%m-%d)
echo "# Date: ${dateString}"

if [ "${OUTPUT}" == "lean" ]; then
  PACKERTARGET="arm64-rpi-lean-image"
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-lean"
  PACKERFINALFILE="raspiblitz-min-${codeVersion}-${dateString}"
elif [ "${OUTPUT}" == "fat" ]; then
  PACKERTARGET="arm64-rpi-fatpack-image" 
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/TODO" #TODO
  PACKERFINALFILE="raspiblitz-fat-${codeVersion}-${dateString}"
elif [ "${OUTPUT}" == "x86" ]; then
  PACKERTARGET="amd64-lean-server-legacyboot-image" 
  PACKERBUILDPATH="./raspiblitz/ci/amd64/TODO" #TODO
  PACKERFINALFILE="raspiblitz-amd64-${codeVersion}-${dateString}"
else
  echo "error='output $OUTPUT not supported'"
  exit 1
fi

echo "# PACKER TARGET: ${PACKERTARGET}"
echo "# PACKER BUILD PATH: ${PACKERBUILDPATH}"
echo "# PACKER FINAL FILE: ${PACKERFINALFILE}"

# prevet monitor to go to sleep during long non-inetractive build
xset s off
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false

echo "# BUILDING '${PACKERTARGET}' ###########################################"
make $PACKERTARGET

# check if build was successful
if [ $? -gt 0 ]; then
  echo "# BUILDING FAILED ###########################################"
  echo "# Check the output above for errors."
  exit 1
fi

echo "# BUILDING SUCESS ###########################################"

echo "# moving build to timestamped folder ./${BUILDFOLDER}"
cd ..
mkdir "${BUILDFOLDER}"
if [ $? -gt 0 ]; then
  echo "# FAILED CREATING FOLDER: ${BUILDFOLDER}"
  exit 1
fi
mv "${PACKERBUILDPATH}.img.gz" "./${BUILDFOLDER}/${PACKERFINALFILE}.img.gz"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .img.gz"
  exit 1
fi
mv "${PACKERBUILDPATH}.img.gz.sha256" "./${BUILDFOLDER}/${PACKERFINALFILE}.img.gz.sha256"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .img.gz.sha256"
  exit 1
fi
mv "${PACKERBUILDPATH}.img.sha256" "./${BUILDFOLDER}/${PACKERFINALFILE}.img.sha256"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .img.sha256"
  exit 1
fi


echo "# clean up"
rm -rf raspiblitz 2>/dev/null

echo "# SIGN & SECURE IMAGE ###########################################"
echo

# security check that internet is cut
echo "# MANUAL ACTION NEEDED:"
echo "# Cut the connection to the internet before signing the image."
echo
echo "# Press RETURN to continue..."
read -r -p "" key
if ping -c 1 "1.1.1.1" &> /dev/null; then
    echo "# FAIL - Internet connection is up - EXITING SCRIPT"
    exit 1
else
    echo "# OK - Internet connection is cut"
fi
echo

# Note down the SHA256 checksum of the image
echo "# MANUAL ACTION NEEDED:"
echo "# Note down the SHA256 checksum of the image:"
echo
cat ./${BUILDFOLDER}/${PACKERFINALFILE}.img.gz.sha256
echo 
echo "# Press RETURN to continue..."
read -r -p "" key

# import the signer keys
echo "# MANUAL ACTION NEEDED:"
echo "# Keep this terminal open and the 128GB stick connected."
echo "# Additionalley connect and unlock the USB device with the signer keys."
echo "# Open in Filemanager and use right-click 'Open in Termonal' and run:"
echo "# sudo gpg --import ./sub.key"
echo "# Close that second terminal and remove USB device with signer keys."
echo 
echo "# Press RETURN to continue..."
read -r -p "" key

# signing instructions
echo "# MANUAL ACTION NEEDED:"
echo "# Please wait infront of the screen until the signing process is asks you for the password."
echo
cd "${BUILDFOLDER}"
gpg --output ${PACKERFINALFILE}.img.gz.sig --detach-sign ${PACKERFINALFILE}.img.gz
if [ $? -gt 0 ]; then
  echo "# !!!!!!! SIGNING FAILED - redo manual before closing this terminbal !!!!!!!"
  echo "gpg --output ${PACKERFINALFILE}.img.gz.sig --detach-sign ${PACKERFINALFILE}.img.gz"
else
  echo "# OK Signing successful."
fi

# last notes
echo
echo "Close this terminal and eject your 128GB usb device."
echo "Have fun with your build image on it under:"
echo "${BUILDFOLDER}/${PACKERBUILDFILE}.img.gz"