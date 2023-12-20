#!/usr/bin/env bash

#########################################################################
# script to trigger packer image build on a debian LIVE system
# see FAQ.dev.md for instructions
##########################################################################

# YOUR REPO (REPLACE WITH YOUR OWN FORK IF NEEDED)
REPO="https://github.com/raspiblitz/raspiblitz"

echo "Build RaspiBlitz install images on a Debian LIVE system"
echo "From repo (change in script is needed):"
echo $REPO

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

if [ "${OUTPUT}" == "lean" ]; then
  PACKERTARGET="arm64-rpi-lean-image"
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/"
  PACKERBUILDFILE="raspiblitz-arm64-rpi-lean"
elif [ "${OUTPUT}" == "fat" ]; then
  PACKERTARGET="arm64-rpi-fatpack-image" 
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/TODO" #TODO
  PACKERBUILDFILE="TODO" #TODO
elif [ "${OUTPUT}" == "x86" ]; then
  PACKERTARGET="amd64-lean-server-legacyboot-image" 
  PACKERBUILDPATH="./raspiblitz/ci/amd64/TODO" #TODO
  PACKERBUILDFILE="TODO" #TODO
else
  echo "error='output $OUTPUT not supported'"
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
cd raspiblitz

# checkout the desired branch
git checkout $BRANCH

# prevet monitor to go to sleep during long non-inetractive build
xset s off

echo "# BUILDING '${PACKERTARGET}' ###########################################"
make $PACKERTARGET

# check if build was successful
if [ $? -gt 0 ]; then
  echo "# BUILDING FAILED ###########################################"
  echo "# Check the output above for errors."
  exit 1
fi

echo "# BUILDING SUCESS ###########################################"

TIMESTAMP=$(date +%s)
echo "# moving build to timestamped folder ./${TIMESTAMP}"
mkdir "${TIMESTAMP}"
if [ $? -gt 0 ]; then
  echo "# FAILED CREATING FOLDER: ${TIMESTAMP}"
  exit 1
fi
mv "${PACKERBUILDPATH}${PACKERBUILDFILE}.img.gz" "./${TIMESTAMP}/${PACKERBUILDFILE}.img.gz"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .img.gz"
  exit 1
fi
mv "${PACKERBUILDPATH}${PACKERBUILDFILE}.img.gz.sha256" "./${TIMESTAMP}/${PACKERBUILDFILE}.img.gz.sha256"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .img.gz.sha256"
  exit 1
fi
mv "${PACKERBUILDPATH}${PACKERBUILDFILE}.img.sha256" "./${TIMESTAMP}/${PACKERBUILDFILE}.img.sha256"
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
cat ./${TIMESTAMP}/${PACKERBUILDFILE}.img.gz.sha256
echo 
echo "# Press RETURN to continue..."
read -r -p "" key

# import the signer keys
echo "# MANUAL ACTION NEEDED:"
echo "# Keep this terminal open and the 128GB stick connected."
echo "# Additionalley connect and unlock the USB device with the signer keys."
echo "# Open in Filemanager and use right-click 'Open in Termonal' and run:"
echo "# gpg --import ./sub.key"
echi "# Close that second terminal and remove USB device with signer keys."
echo 
echo "# Press RETURN to continue..."
read -r -p "" key

# signing instructions
echo "# MANUAL ACTION NEEDED:"
echo "# Please wait infront of the screen until the signing process is asks you for the password."
echo
cd "${TIMESTAMP}"
gpg --output ${PACKERBUILDFILE}.img.gz.sig --detach-sign ${PACKERBUILDFILE}.img.gz
if [ $? -gt 0 ]; then
  echo "# !!!!!!! SIGNING FAILED - redo manual before closing this terminbal !!!!!!!"
  echo "gpg --output ${PACKERBUILDFILE}.img.gz.sig --detach-sign ${PACKERBUILDFILE}.img.gz"
else
  echo "# OK Signing successful."
fi

# last notes
echo
echo "Close this terminal and eject your 128GB usb device."
echo "Have fun with your build image on it under:"
echo "${TIMESTAMP}/${PACKERBUILDFILE}.img.gz"