#!/bin/bash -e

# set vars
echo "# Setting the variables: $*"
source ../set_variables.sh
set_variables "$@"

# build the image in docker
echo -e "\nBuild the image..."
# from https://hub.docker.com/r/mkaczanowski/packer-builder-arm/tags
command="docker run --rm --privileged -v /dev:/dev -v ${PWD}:/build \
  mkaczanowski/packer-builder-arm@sha256:0ff8ce0cf33e37be6c351c8bcb2643835c7f3525b7f591808b91c04238d45695 \
  build ${vars} build.arm64-rpi.pkr.hcl"
echo "# Running: $command"
$command || exit 1
