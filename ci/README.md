<!-- omit in toc -->
# Automated builds
* The images are built using the dev branch.
* The lean image has no Gnome desktop or WebUI installed.
* Issue: https://github.com/rootzoll/raspiblitz/issues/3053
* The templates are made using: https://github.com/chef/bento

- [Local build](#local-build)
  - [Generate an arm64-rpi image](#generate-an-arm64-rpi-image)
  - [Generate an amd64 image](#generate-an-amd64-image)
- [Images generated in github actions](#images-generated-in-github-actions)
- [Write the image to a disk connected with USB](#write-the-image-to-a-disk-connected-with-usb)
  - [Convert the qcow2 volume to a raw disk image](#convert-the-qcow2-volume-to-a-raw-disk-image)
  - [Write to a disk connected with USB with Balena Etcher or `dd`](#write-to-a-disk-connected-with-usb-with-balena-etcher-or-dd)
  - [Extend the partition on the new disk (optional)](#extend-the-partition-on-the-new-disk-optional)
- [The first boot](#the-first-boot)
  - [fatpack image](#fatpack-image)
  - [lean image](#lean-image)
    - [Add Gnome desktop (optional)](#add-gnome-desktop-optional)
  - [Add wifi (optional)](#add-wifi-optional)
  - [Add wifi driver (optional)](#add-wifi-driver-optional)
- [Workflow notes](#workflow-notes)
  - [Packer .json settings:](#packer-json-settings)
  - [VNC](#vnc)
  - [Flashing](#flashing)

## Local build
with the [Makefile](https://github.com/rootzoll/raspiblitz/blob/dev/Makefile)
* needs ~20 GB free space
* tested on:
  * Ubuntu Live (jammy)
  * Debian Bullseye Desktop
* Preparation:
  ```
  # change to a mountpoint with sufficient space (check with 'df -h')
  cd $HOME/
  # switch to root
  sudo su
  # install git and make
  apt update && apt install -y git make
  # download the repo (or your fork)
  git clone https://github.com/rootzoll/raspiblitz
  cd raspiblitz
  # checkout the desired branch
  git checkout dev
  ```

### Generate an arm64-rpi image
* The workflow locally and in github actions generates a .img raw format image for the Raspberry Pi.
  ```
  make arm-rpi-lean-image
  ```
* find the image and sha256 hashes in the `ci/arm64-rpi/packer-builder-arm` directory
* the .img.gz file can be written to an SDcard directly with Balena Etcher

### Generate an amd64 image with gnome desktop
The workflow locally and in github actions generates a .qcow2 format amd64 image.
* Tested with
  * libvirt / virsh / virt-manager (https://virt-manager.org/)
  * written to disk and booted with legacy boot (non-UEFI)
  ```
  make amd64-lean-desktop-image
  ```
* find the compressed .qcow2 image and sha256 hashes in the `ci/amd64/builds` directory

## Images generated in github actions
* To see the downloadable artifacts will need to log in to GitHub
* Find the latest successful builds for amd64 using the dev branch at:  
https://github.com/rootzoll/raspiblitz/actions/workflows/amd64-lean-image.yml?query=workflow%3Aamd64-lean-image-build+branch%3Adev+is%3Asuccess++
  ```
  # unzip to the same directory
  unzip raspiblitz-amd64-image-YEAR-MM-DD-COMMITHASH.zip
  ```
## Write the image to a disk connected with USB
### Convert the qcow2 volume to a raw disk image
* the raw image is 30GB
  ```
  # unzip
  gzip -dkv raspiblitz-amd64-debian-lean.qcow2.gz
  # convert
  qemu-img convert raspiblitz-amd64-debian-lean.qcow2 raspiblitz-amd64-debian-lean.img
  ```

### Write to a disk connected with USB with Balena Etcher or `dd`
* identify the connected disk with `lsblk` eg,: `/dev/sdk`
* [Balena Etcher](https://www.balena.io/etcher/) to write the .img to disk
* dd to write the .img to disk
  ```
  sudo dd if=./raspiblitz-amd64-debian-lean.img of=/dev/sdk bs=4M status=progress
  ```
* qemu-image dd to write the .qcow2 directly to disk
  ```
  sudo apt install -y qemu-utils
  sudo qemu-img dd if=./raspiblitz-amd64-debian-lean.qcow2 of=/dev/sde bs=4M
  ```
### Extend the partition on the new disk (optional)
* GUI: use GParted to resize the Extended Partition to the full size of the disk
  ```
  # install
  sudo apt install gparted
  # run
  sudo gparted
  ```
* CLI:
  ```
  # identify the USB connected disk
  lsblk
  df -h
  # extend the lvm to the full free space and resize the filesystem
  sudo lvextend -r -l +100%FREE /dev/mapper/raspiblitz--amd64--debian--11--vg-root

  # alternatively download the script
  git clone https://git.scs.carleton.ca/git/extend-lvm.git
  # run with the disk as the parameter (sdk for example)
  sudo bash extend-lvm/extend-lvm.sh /dev/sdk
  ```

## The first boot
### the default image with desktop
* log in on screen:
  * username: `admin`
  * password: `raspiblitz`

* start a terminal for guidance

* alternatively open a browser and go to:
  * http://localhost
* can also open the WebUI on another computer
  * Find the the RaspiBlitz_IP in your router dashboard, in the terminal prompt or with `hostname -I`
  * open: http://RaspiBlitz_IP

### lean image
* press any key to get to a login prompt after the splash screen
  * username: `admin`
  * password: `raspiblitz`

#### Add Gnome desktop to the server image (optional)
* Connect to the internet (easiest to plug in a LAN cable - use a USB - LAN adapter if have no port)
  ```
  apt install gnome
  systemctl start gdm
  ```

### Add wifi (optional)
* if the wifi driver is included in the FOSS Debian distro
* in the command line run the network manager interface to connect:
  ```
  sudo nmtui
  ```
### Add wifi driver (optional)
* as in https://wiki.debian.org/iwlwifi
* add the component `non-free` after `deb http://deb.debian.org/debian bullseye main` in `/etc/apt/sources.list`
* install the wifi driver for the mentioned cards:
  ```
  sudo apt update && sudo apt install firmware-iwlwifi
  ```
* alternatively download the deb package from: http://ftp.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/firmware-iwlwifi_20230210-5_all.deb
* install with:
  ```
  sudo dpkg -i firmware-iwlwifi_20230210-5_all.deb
  ```

## Workflow notes
The github workflow files are the equivalent of the Makefile commands run locally.
The local repo owner (`GITHUB_ACTOR`) and branch (`GITHUB_HEAD_REF`) is picked up.
The build_sdcard.sh is downloaded from the source branch and built with the options pack=[lean|fatpack] to set fatpack=[0|1].

The github workflow is running the job in an ubuntu-22.04 image.

The amd64 image is built with running a qemu VM
* installs the base OS (Debian)
* connects with ssh and runs the scripts including the build_sdcard.sh

The arm64-rpi image generation runs in Docker in github actions and without Docker locally.
* the base image (RaspberryOS) is started in the qemu VM
* Packer runs the build_sdcard.sh directly in the VM

After the image is built (and there is no exit with errors) the next steps are:
* compute checksum of the qemu/raw image
* compress the image with gzip
* compute checksum of the compressed image
* (in github actions: upload the artifacts in one .zip file)

### Packer .json settings:
* `disk_size` - the size op the raw image. The .qcow2 file is compressed.
* `template`  - image filename
* `output_directory` - directory under builds where the image will be placed
* the `pi` user is given passwordless sudo access and used for the image setup
* use `file_checksum`  instead of `file_checksum_url`. The image must be downloaded and verified with PGP manually to fill the field:
  ```
  # image
  wget https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2022-09-26/2022-09-22-raspios-bullseye-arm64.img.xz
  # signature
  wget https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2022-09-26/2022-09-22-raspios-bullseye-arm64.img.xz.sig
  # hash
  wget https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2022-09-26/2022-09-22-raspios-bullseye-arm64.img.xz.sha256

  curl https://www.raspberrypi.org/raspberrypi_downloads.gpg.key | gpg --import

  sha256sum -c 2022-09-22-raspios-bullseye-arm64.img.xz.sha256 && \
  gpg --verify 2022-09-22-raspios-bullseye-arm64.img.xz.sig

  cat 2022-09-22-raspios-bullseye-arm64.img.xz.sha256
  ```
### VNC
* can follow the setup locally in VNC with the port stated in the first part of the logs eg: `Found available VNC port: 5952 on IP: 127.0.0.1`
### Flashing
* using `qemu-img dd bs=4M if=raspiblitz-amd64-debian-lean.qcow2 of=/dev/sdd` changed the UUID so it won't boot without editing GRUB
