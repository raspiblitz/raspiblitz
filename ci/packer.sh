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
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-lean"
elif [ "${OUTPUT}" == "fat" ]; then
  PACKERTARGET="arm64-rpi-fatpack-image" 
  PACKERBUILDPATH="./raspiblitz/ci/arm64-rpi/packer-builder-arm/TODO" #TODO
elif [ "${OUTPUT}" == "x86" ]; then
  PACKERTARGET="amd64-lean-server-legacyboot-image" 
  PACKERBUILDPATH="./raspiblitz/ci/amd64/TODO" #TODO
else
  echo "error='output $OUTPUT not supported'"
  exit 1
fi

# check if build was successful
if [ $? -gt 0 ]; then
  echo "# BUILDING FAILED ###########################################"
  echo "# Check the output above for errors."
  exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root / may use sudo'"
  exit 1
fi

# switch to root
sudo su

# install git and make
apt update && apt install -y git make

# clean old repo
rm -rf raspiblitz 2>/dev/null

# download the repo
git clone $REPO
cd raspiblitz

# checkout the desired branch
git checkout $BRANCH

echo "# BUILDING '${PACKERTARGET}' ###########################################"
make $PACKERTARGET

# check if build was successful
if [ $? -gt 0 ]; then
  echo "# BUILDING FAILED ###########################################"
  echo "# Check the output above for errors."
  exit 1
fi

echo "# BUILDING SUCESS ###########################################"

echo "# moving build to timestamped folder"
TIMESTAMP=$(date +%s)
mkdir $TIMESTAMP
mv $PACKERBUILDPATH.img.gz ./$TIMESTAMP
mv $PACKERBUILDPATH.img.gz.sha256 ./$TIMESTAMP
mv $PACKERBUILDPATH.img.sha256 ./$TIMESTAMP

echo "# TODO: CLEAN UP OLD BUILDS"
echo "# TODO: CUT INTERNET & SIGN IMAGE"