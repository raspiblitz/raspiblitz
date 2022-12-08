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
  pack=$1
else
  pack=lean
fi

if [ $# -gt 1 ]; then
  github_user=$2
else
  github_user=rootzoll
fi

if [ $# -gt 2 ]; then
  branch=$3
else
  branch=dev
fi

# Build the image
echo -e "\nBuilding image..."
cd debian
PACKER_LOG=1 packer build \
 --var pack=${pack} --var github_user=${github_user} --var branch=${branch}  \
 -only=qemu amd64-debian.json
