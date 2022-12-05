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

if [ $# -gt 0 ]; then
  github_user=$1
else
  github_user=rootzoll
fi

if [ $# -gt 1 ]; then
  branch=$2
else
  branch=dev
fi

# Build the image
echo -e "\nBuilding image..."
cd debian
PACKER_LOG=1 packer build --var github_user=${github_user} --var branch=${branch} -only=qemu debian-11.5-amd64-lean.json
