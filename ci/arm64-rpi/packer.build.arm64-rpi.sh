#!/bin/bash -e

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

# Build the image in docker
echo -e "\nBuild Packer image..."
# from https://hub.docker.com/r/mkaczanowski/packer-builder-arm/tags
docker run --rm --privileged -v /dev:/dev -v ${PWD}:/build \
 mkaczanowski/packer-builder-arm:1.0.4@sha256:df09a8e249a292f10ca9b8cfd73420f5b987b6ac337d4ef28b6f4a8e61118822 \
 build -var github_user=${github_user} -var branch=${branch} -var pack=${pack} arm64-rpi.pkr.hcl
