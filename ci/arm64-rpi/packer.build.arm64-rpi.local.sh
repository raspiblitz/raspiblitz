#!/bin/bash -e

echo -e "\n# Install dependencies with apt"
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
  sudo apt-get update -y && sudo apt-get install packer=1.10.0-1 -y || exit 1
else
  echo "# Packer is installed"
fi

echo -e "\n# Install Go"
export PATH=$PATH:/usr/local/go/bin
# https://go.dev/dl/
GOVERSION="1.20.6"
GOHASH="b945ae2bb5db01a0fb4786afde64e6fbab50b67f6fa0eb6cfa4924f16a7ff1eb"
if ! go version 2>/dev/null | grep "${GOVERSION}"; then
  wget --progress=bar:force https://go.dev/dl/go${GOVERSION}.linux-amd64.tar.gz
  echo "${GOHASH} go${GOVERSION}.linux-amd64.tar.gz" | sha256sum -c - || exit 1
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go${GOVERSION}.linux-amd64.tar.gz
  sudo rm -rf go${GOVERSION}.linux-amd64.tar.gz
else
  echo "# Go ${GOVERSION} is installed"
fi

echo -e "\n# Download the packer-builder-arm plugin"
git clone https://github.com/mkaczanowski/packer-builder-arm
cd packer-builder-arm
# https://github.com/mkaczanowski/packer-builder-arm/releases
git reset --hard "v1.0.9"
echo -e "\n# Build the packer-builder-arm plugin"
go mod download
go build || exit 1

# set vars
echo "# Setting the variables: $*"
# running from the ci/arm64-rpi/packer-builder-arm directory
source ../../set_variables.sh
set_variables "$@"

cp ../build.arm64-rpi.pkr.hcl ./
cp ../build.raspiblitz.sh ./

echo -e "\n# Build the image"
command="packer build ${vars} build.arm64-rpi.pkr.hcl"
echo "# Running: $command"
$command || exit 1
