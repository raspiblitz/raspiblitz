<!-- omit in toc -->
# Automated builds

<details>
<summary>Table of Contents</summary>

- [Ready made images for arm64-rpi](#ready-made-images-for-arm64-rpi)
- [Ready made images for amd64 (x86)](#ready-made-images-for-amd64-x86)
  - [Write the image to a disk connected with USB](#write-the-image-to-a-disk-connected-with-usb)
    - [Prepare the disk](#prepare-the-disk)
    - [Option 1 - rite the .qcow2 file directly to disk with `qemu-image dd`](#option-1---rite-the-qcow2-file-directly-to-disk-with-qemu-image-dd)
    - [Option 2 - convert the .qcow2 volume to a raw disk image](#option-2---convert-the-qcow2-volume-to-a-raw-disk-image)
  - [The first boot](#the-first-boot)
    - [Lean image with Gnome desktop (default image)](#lean-image-with-gnome-desktop-default-image)
    - [Extend the root partition (optional - recommended)](#extend-the-root-partition-optional---recommended)
    - [Add wifi driver (optional)](#add-wifi-driver-optional)
- [Local build](#local-build)
  - [Generate an arm64-rpi image](#generate-an-arm64-rpi-image)
  - [Generate an amd64 image](#generate-an-amd64-image)
    - [amd64-lean-desktop-uefi-image](#amd64-lean-desktop-uefi-image)
    - [amd64-lean-server-legacyboot-image](#amd64-lean-server-legacyboot-image)
- [Notes for the lean server image without Gnome desktop](#notes-for-the-lean-server-image-without-gnome-desktop)
  - [After the boot](#after-the-boot)
  - [Connect to wifi from the command line (optional)](#connect-to-wifi-from-the-command-line-optional)
    - [Add Gnome desktop to the server image (optional)](#add-gnome-desktop-to-the-server-image-optional)
- [Fatpack images](#fatpack-images)
- [Workflow notes](#workflow-notes)
  - [VNC](#vnc)
  - [Packer settings](#packer-settings)
  - [Flashing](#flashing)

</details>

## Ready made images for arm64-rpi
* The images are built in GitHub actions
* To see the downloadable artifacts will need to log in to GitHub
* Find the latest successful build of the default amd64 image:
https://github.com/raspiblitz/raspiblitz/actions/workflows/arm64-rpi-lean-image.yml?query=workflow%3Aarm64-rpi-lean-image-build+is%3Asuccess+branch%3Adev
* unpack the artifact to the same directory
  ```
  unzip ./raspiblitz-arm64-rpi-image-*.zip
  ```
* The resulting `raspiblitz-arm64-rpi-lean.img.gz` can be written to an SDcard directly with Balena Etcher


## Ready made images for amd64 (x86)
* The images are built in GitHub actions
* To see the downloadable artifacts will need to log in to GitHub
* Find the latest successful build of the default amd64 image:
https://github.com/rootzoll/raspiblitz/actions/workflows/amd64-lean-image.yml?query=workflow%3Aamd64-lean-image-build+branch%3Adev+is%3Asuccess++
  ```
  # unpack the artifact to the same directory
  unzip ./raspiblitz-amd64-image-*.zip
  # unpack the image
  gzip -dkv raspiblitz-amd64-debian-lean.qcow2.gz
  # install qemu-utils
  sudo apt install -y qemu-utils
  ```
###  Write the image to a disk connected with USB

#### Prepare the disk
* identify the connected disk with `lsblk` e.g., `/dev/sdk`
* set the disk variable
  ```
  # identify the USB connected disk
  lsblk
  # set the disk variable
  disk=/dev/sdk
  ```
* clean the existing partitions:
  ```
  # unmount all partitions
  sudo umount ${disk}*
  # wipe the partition table
  sudo wipefs --all ${disk}
  ```

#### Option 1 - rite the .qcow2 file directly to disk with `qemu-image dd`
* requires less disk space - the .qcow2 volume is 8.1 GB
  ```
  sudo qemu-img dd if=./raspiblitz-amd64-debian-lean.qcow2 of=${disk} bs=4M
  ```

#### Option 2 - convert the .qcow2 volume to a raw disk image
* the raw .img is 30GB
  ```
  # convert
  qemu-img convert ./raspiblitz-amd64-debian-lean.qcow2 ./raspiblitz-amd64-debian-lean.img
  ```
* identify the connected disk with `lsblk` e.g., `/dev/sdk`
* use [Balena Etcher](https://www.balena.io/etcher/)
* or `dd` to write the .img to disk
  ```
  sudo dd if=./raspiblitz-amd64-debian-lean.img of=${disk} bs=4M status=progress
  ```

### The first boot
#### Lean image with Gnome desktop (default image)
* log in on screen:
  * username: `admin`
  * password: `raspiblitz`
* start a terminal for guidance
* alternatively connect with ssh over the LAN with the same username and password

#### Extend the root partition (optional - recommended)
* The default image is 30GB. The partition can be extended to the full size of the disk.
* The lvm partition can be extended while mounted so this step can be done later as well while the system is running.
* CLI (recommended)
  ```
  # identify the USB connected disk
  lsblk
  df -h
  # select the disk carefully
  disk="/dev/sde"
  # resize the extended partition to the full size of the disk
  sudo parted ${disk} -- resizepart 2 100%
  # resize the lvm partition to the full size of the disk
  sudo parted ${disk} -- resizepart 5 100%
  # extend the physical volume to size of the lvm partition
  sudo pvresize ${disk}5
  # extend the root lvm to the full free space and resize the filesystem
  sudo lvextend -r -l +100%FREE /dev/mapper/raspiblitz--amd64--vg-root
  ```
* GUI with GParted
  ```
  # install
  sudo apt install gparted
  # start the gparted GUI
  sudo gparted
  # resize the extended partition to the full size of the disk
  # extend the lvm to the full free space and resize the filesystem (extends the swap space by default)
  # in CLI: extend the root lvm
  sudo lvextend -r -l +100%FREE /dev/mapper/raspiblitz--amd64--vg-root
  ```

#### Add wifi driver (optional)
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
  make arm64-rpi-lean-image
  ```
* find the image and sha256 hashes in the `ci/arm64-rpi/packer-builder-arm` directory
* the .img.gz file can be written to an SDcard directly with Balena Etcher

### Generate an amd64 image
* The workflow locally and in github actions generates a .qcow2 format amd64 image.
* When finished find the compressed .qcow2 image and sha256 hashes in the `ci/amd64/builds` directory

#### amd64-lean-desktop-uefi-image
* lean image, Gnome desktop, UEFI boot
* Tested with
  * written to disk and booted with UEFI
  ```
  make amd64-lean-desktop-uefi-image
  ```

#### amd64-lean-server-legacyboot-image
* lean image, no desktop (cli only), legacy boot for old computers
* Tested with
  * libvirt / virsh / virt-manager (https://virt-manager.org/)
  * written to disk and booted with legacy boot (non-UEFI / CSM mode)
  ```
  make amd64-lean-server-legacyboot-image
  ```

## Notes for the lean server image without Gnome desktop
### After the boot
* press any key to get to a login prompt after the splash screen
  * username: `admin`
  * password: `raspiblitz`

### Connect to wifi from the command line (optional)
* if the wifi driver is included in the FOSS Debian distro
* in the command line run the network manager interface to connect:
  ```
  sudo nmtui
  ```

#### Add Gnome desktop to the server image (optional)
* Connect to the internet (easiest to plug in a LAN cable - use a USB - LAN adapter if have no port)
  ```
  apt install gnome
  systemctl start gdm
  ```

## Fatpack images
* can open a browser and go to:
  * http://localhost
* can also open the WebUI on another computer
  * Find the the RaspiBlitz_IP in your router dashboard, in the terminal prompt or with `hostname -I`
  * open: http://RaspiBlitz_IP

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

### VNC
* can follow the setup locally in VNC with the port stated in the first part of the logs eg: `Found available VNC port: 5900 on IP: 127.0.0.1`

### Packer settings
* `disk_size` / `image_size` - the size op the raw image. The .qcow2 file is compressed.
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
### Flashing
* using `qemu-img dd bs=4M if=raspiblitz-amd64-debian-lean.qcow2 of=/dev/sdd` changed the UUID so it won't boot without editing GRUB
