#!/bin/bash -e

sudo apt-get update

# install packer
if ! packer version 2>/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update
  echo -e "\nInstalling packer..."
  sudo apt-get install -y packer
else
  echo "# Packer is installed"
fi



# install qemu
echo "# Install qemu ..."
sudo apt-get update
sudo apt-get install -y qemu-system

# set vars
source ../set_variables.sh
set_variables "$@"

# Build the image
echo "# Build the image ..."
cd debian
packer init -upgrade .
command="PACKER_LOG=1 packer build ${vars} -only=qemu packer.build.amd64-debian.hcl"
echo "# Running: $command"
if [ ${#vars} -eq 0 ];then exit 1;fi
PACKER_LOG=1 packer build ${vars} -only=qemu.debian build.amd64-debian.pkr.hcl || exit 1
