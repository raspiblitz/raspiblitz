#!/bin/bash -e

# Install packer
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update
echo -e "\nInstalling packer..."
sudo apt-get install -y packer

# Install qemu
echo -e "\nInstalling qemu..."
sudo apt-get install -y qemu-system

# set vars
source ../set_variables.sh
set_variables "$@"

# Build the image
echo -e "\nBuilding image..."
cd debian
PACKER_LOG=1 packer build ${vars} -only=qemu amd64-debian.json
