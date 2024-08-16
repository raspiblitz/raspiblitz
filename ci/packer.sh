#!/usr/bin/env bash

#########################################################################
# script to trigger packer image build on a debian LIVE system
# see FAQ.dev.md for instructions
##########################################################################

# YOUR REPO (REPLACE WITH YOUR OWN FORK IF NEEDED)
REPO="https://github.com/raspiblitz/raspiblitz"

# folders to store the build results
BUILDFOLDER="images"

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root / may use sudo'"
  exit 1
fi

# usage info
echo "packer.sh [BRANCH] [arm|x86] [min|fat] [?lastcommithash]"
echo "Build RaspiBlitz install images on a Debian LIVE system"
echo "From repo (change in script is needed):"
echo $REPO
echo "Results will be stored in:"
echo $BUILDFOLDER
echo "Start this script in the root of an writable 128GB NTFS formatted USB drive."

# check if internet is available
if ping -c 1 "1.1.1.1" &> /dev/null; then
  echo "# checking internet"
else
  echo "error='script needs internet connection to run'"
  exit 1
fi

# get parameters
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then

  # by input
  read -p "Press ENTER to continue or CTRL+C to exit"
  read -p "Enter the branch to build: " BRANCH
  read -p "Enter the architecture to build (arm|x86): " ARCH
  read -p "Enter the type to build (min|fat): " TYPE
  read -p "Enter the last commit hash to check (optional): " COMMITHASH

else

  # by command line
  BRANCH=$1
  ARCH=$2
  TYPE=$3
  COMMITHASH=$4
  
fi

# check if branch is set
if [ ${#BRANCH} -eq 0 ]; then
  echo "error='branch not set'"
  exit 1
fi

# check if arch is set
if [ ${#ARCH} -eq 0 ]; then
  echo "error='ARCH not set'"
  exit 1
fi
if [ "$ARCH" != "arm" ] && [ "$ARCH" != "x86" ]; then
  echo "error='ARCH not supported'"
  exit 1
fi

# check if type is set
if [ ${#TYPE} -eq 0 ]; then
  echo "error='TYPE not set'"
  exit 1
fi
if [ "$TYPE" != "min" ] && [ "$TYPE" != "fat" ]; then
  echo "error='TYPE not supported'"
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
if [ $? -gt 0 ]; then
  cd ..
  rm -rf raspiblitz 2>/dev/null
  echo "# BRANCH: ${BRANCH}"
  echo "error='git checkout BRANCH failed'"
  exit 1
fi

# check commit hash if set
if [ ${#COMMITHASH} -gt 0 ]; then
  echo "# CHECKING COMMITHASH"
  actualCOMMITHASH=$(git log -1 --format=%H)
  echo "# actual(${actualCOMMITHASH}) ?= wanted(${COMMITHASH})"
  matches=$(echo "${actualCOMMITHASH}" | grep -c "${COMMITHASH}")
  if [ ${matches} -eq 0 ]; then
    cd ..
    rm -rf raspiblitz 2>/dev/null
    echo "error='COMMITHASH of branch does not match'"
    exit 1
  fi
  echo "# COMMITHASH CHECK OK"
else
  echo "# NO COMMITHASH CHECK"
fi

# make sure make build runs thru
safedir=$(realpath ./ci/arm64-rpi/packer-builder-arm)
echo "# Setting safe.directory to: ${safedir}"
git config --global --add safe.directory "${safedir}"

# get code version
codeVersion=$(cat ./home.admin/_version.info | grep 'codeVersion="' | cut -d'"' -f2)
if [ ${#codeVersion} -eq 0 ]; then
  echo "error='codeVersion not found'"
  exit 1
fi
echo "# RaspiBlitz Version: ${codeVersion}"

# get date as string formatted like YEAR-MONTH-DAY
dateString=$(date +%Y-%m-%d)
echo "# Date: ${dateString}"

if [ "${ARCH}" == "arm" ] && [ "${TYPE}" == "min" ]; then
  PACKERTARGET="arm64-rpi-lean-image"
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-lean.img"
  PACKERFINALFILE="raspiblitz-min-v${codeVersion}-${dateString}.img"
elif [ "${ARCH}" == "arm" ] && [ "${TYPE}" == "fat" ]; then
  PACKERTARGET="arm64-rpi-fatpack-image" 
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-fat.img"
  PACKERFINALFILE="raspiblitz-fat-v${codeVersion}-${dateString}.img"
elif [ "${ARCH}" == "x86" ] && [ "${TYPE}" == "min" ]; then
  PACKERTARGET="amd64-lean-server-legacyboot-image"
  PACKERBUILDPATH="./raspiblitz/ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu/raspiblitz-amd64-debian-lean.qcow2"
  PACKERFINALFILE="raspiblitz-amd64-min-v${codeVersion}-${dateString}.qcow2"
else
  echo "error='$ARCH-$TYPE not supported'"
  exit 1
fi

echo "# PACKER TARGET: ${PACKERTARGET}"
echo "# PACKER BUILD PATH: ${PACKERBUILDPATH}"
echo "# PACKER FINAL FILE: ${PACKERFINALFILE}"

# check if file already exists
if [ -f "./${BUILDFOLDER}/${PACKERFINALFILE}.img.gz" ]; then
  echo "error='image already exists'"
  echo "# delete ./${BUILDFOLDER}/${PACKERFINALFILE}.img.gz (and all .sha256 & .sig) before trying again"
  exit 1
fi

# prevent monitor to go to sleep during long non-interactive build
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

echo "# BUILDING SUCCESS ###########################################"

echo "# moving build to timestamped folder ./${BUILDFOLDER}"
cd ..
mkdir "${BUILDFOLDER}" 2>/dev/null

# check that Build folder exists
if [ ! -d "./${BUILDFOLDER}" ]; then
  echo "# FAILED CREATING BUILD FOLDER: ./${BUILDFOLDER}"
  exit 1
fi

# move .gz file to build folder
mv "${PACKERBUILDPATH}.gz" "./${BUILDFOLDER}/${PACKERFINALFILE}.gz"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .gz"
  exit 1
fi

# move gz.sha256 file to build folder
mv "${PACKERBUILDPATH}.gz.sha256" "./${BUILDFOLDER}/${PACKERFINALFILE}.gz.sha256"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .gz.sha256"
  exit 1
fi

# move sha256 file to build folder
mv "${PACKERBUILDPATH}.sha256" "./${BUILDFOLDER}/${PACKERFINALFILE}.sha256"
if [ $? -gt 0 ]; then
  echo "# FAILED MOVING .sha256"
  exit 1
fi

# special handling for qcow2
if [ "${ARCH}" == "x86" ]; then
  echo "# decompressing qcow2"
  gunzip "./${BUILDFOLDER}/${PACKERFINALFILE}.gz"
  echo "# converting qcow2 to raw"
  qemu-img convert -f qcow2 -O raw "./${BUILDFOLDER}/${PACKERFINALFILE}.qcow2" "./${BUILDFOLDER}/${PACKERFINALFILE}.img"
  if [ $? -gt 0 ]; then
    echo "# FAILED CONVERTING qcow2 to raw"
    exit 1
  fi
  echo "# compressing raw"
  gzip -9 "./${BUILDFOLDER}/${PACKERFINALFILE}.img"
  if [ $? -gt 0 ]; then
    echo "# FAILED COMPRESSING raw"
    exit 1
  fi
  echo "# removing raw"
  rm "./${BUILDFOLDER}/${PACKERFINALFILE}.img"
  if [ $? -gt 0 ]; then
    echo "# FAILED REMOVING raw"
    exit 1
  fi
fi


echo "# clean up"
rm -rf ./../raspiblitz 2>/dev/null

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
cat ./${BUILDFOLDER}/${PACKERFINALFILE}.gz.sha256
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
gpg --output ${PACKERFINALFILE}.gz.sig --detach-sign ${PACKERFINALFILE}.gz
if [ $? -gt 0 ]; then
  echo "# !!!!!!! SIGNING FAILED - redo manual before closing this terminbal !!!!!!!"
  echo "gpg --output ${PACKERFINALFILE}.gz.sig --detach-sign ${PACKERFINALFILE}.gz"
else
  echo "# OK Signing successful."
fi

# last notes
echo
echo "Close this terminal and eject your 128GB usb device."
echo "Have fun with your build image on it under:"
echo "${BUILDFOLDER}/${PACKERFINALFILE}.gz"
