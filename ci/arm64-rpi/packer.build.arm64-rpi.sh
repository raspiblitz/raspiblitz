#!/bin/bash -e

# set vars
source ../set_variables.sh
set_variables "$@"

# Build the image in docker
echo -e "\nBuild Packer image..."
# from https://hub.docker.com/r/mkaczanowski/packer-builder-arm/tags
docker run --rm --privileged -v /dev:/dev -v ${PWD}:/build \
  mkaczanowski/packer-builder-arm@sha256:0ff8ce0cf33e37be6c351c8bcb2643835c7f3525b7f591808b91c04238d45695 \
  build ${vars} arm64-rpi.pkr.hcl
