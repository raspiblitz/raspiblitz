#!/bin/bash -e

echo "\n# Install dependencies with apt"
if [ "$(uname -n)" = "ubuntu" ]; then
  sudo add-apt-repository -y universe
fi

# Install dependencies
# needed on Ubuntu Live ('lsb_release -cs': jammy)
sudo apt install -y qemu-user-static || exit 1

# from https://github.com/mkaczanowski/packer-builder-arm/blob/master/docker/Dockerfile
sudo apt install -y \
  wget \
  curl \
  ca-certificates \
  dosfstools \
  fdisk \
  gdisk \
  kpartx \
  libarchive-tools \
  parted \
  psmisc \
  qemu-utils \
  sudo \
  xz-utils || exit 1

echo -e "\n# Install Packer..."
if ! packer version 2>/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository -y "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update -y && sudo apt-get install packer -y || exit 1
else
  echo "# Packer is installed"
fi

echo -e "\n# Install Go"
export PATH=$PATH:/usr/local/go/bin
if ! go version 2>/dev/null | grep "1.18.9"; then
  wget --progress=bar:force https://go.dev/dl/go1.18.9.linux-amd64.tar.gz
  echo "015692d2a48e3496f1da3328cf33337c727c595011883f6fc74f9b5a9c86ffa8 go1.18.9.linux-amd64.tar.gz" | sha256sum -c - || exit 1
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.18.9.linux-amd64.tar.gz
  sudo rm -rf go1.18.9.linux-amd64.tar.gz
else
  echo "# Go 1.18.9 is installed"
fi

echo -e "\n# Download the packer-builder-arm plugin"
git clone https://github.com/mkaczanowski/packer-builder-arm
cd packer-builder-arm
# pin to commit hash https://github.com/mkaczanowski/packer-builder-arm/commits/master
git reset --hard 6636c687ece53f7d1f5f2b35aa41f0e6132949c4
echo -e "\n# Build the packer-builder-arm plugin"
go mod download
go build || exit 1

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

cp ../arm64-rpi.pkr.hcl ./
cp ../raspiblitz.sh ./

echo -e "\n# Build the image"
packer build -var github_user=${github_user} -var branch=${branch} -var pack=${pack} arm64-rpi.pkr.hcl
