<!-- omit in toc -->
# ⚡️ Alternative platforms for the RaspiBlitz ⚡️
- [Minimum requirements](#minimum-requirements)
  - [Desirable:](#desirable)
- [Virtual Machine](#virtual-machine)
  - [Create the base image](#create-the-base-image)
  - [Building the Raspiblitz scripts](#building-the-raspiblitz-scripts)
  - [Notes:](#notes)
    - [Data drive:](#data-drive)
- [Armbian](#armbian)
- [Ubuntu](#ubuntu)
- [Python upgrade](#python-upgrade)
- [Create an image release for amd64](#create-an-image-release-for-amd64)
  - [Requirements:](#requirements)
  - [Create an NTFS formatted USB Stick / USB disk](#create-an-ntfs-formatted-usb-stick--usb-disk)
  - [Boot Ubuntu Live from USB](#boot-ubuntu-live-from-usb)
  - [Download and verify the base image](#download-and-verify-the-base-image)
  - [Flash the base image to the installation medium](#flash-the-base-image-to-the-installation-medium)
  - [Install Debian to the OS disk](#install-debian-to-the-os-disk)
    - [Install the RaspiBlitz Scripts](#install-the-raspiblitz-scripts)
    - [Prepare the release](#prepare-the-release)
- [Verify the downloaded the image](#verify-the-downloaded-the-image)
  - [Linux instructions](#linux-instructions)
- [Create a torrent](#create-a-torrent)

## Minimum requirements
* ARMv8 or x86 processor (64 bit)
* 1 GB RAM
* 500 GB HDD
* Python >=3.9 (see [how to upgrade below](#python-upgrade) )

### Desirable:
* \> 2GB DDR3 ECC RAM (8GB+ if using ZFS)
* USB 3.0 / SATA / PCIE / NVME connectors
* SSD - multiple disks for redundancy

Specifications of the tested hardware: [hw_comparison.md](hw_comparison.md)

All testers are welcome. Open an issue for your specific board to collaborate and share your experience.

## Virtual Machine

Instructions to run a RaspiBlitz as a VM on a Linux host machine.
The process is similar if you want to run RaspiBlitz on the bare metal.

Tested with:
* Debian image in VirtualBox and linux virt-manager / [cockpit-machines](https://github.com/cockpit-project/cockpit-machines)
* Ubuntu image in VirtualBox and linux virt-manager / [cockpit-machines](https://github.com/cockpit-project/cockpit-machines)
* Debian image in VirtualBox https://github.com/rootzoll/raspiblitz/issues/2756#issuecomment-983532237
* TrueNAS (FreeBSD bhyve) with an Ubuntu VM: https://github.com/rootzoll/raspiblitz/issues/2104#issuecomment-917444238

### Create the base image
* Download and install the base OS on an at least 32GB drive
* Debian is the most tested and is closest to the RaspberryOS: <https://www.debian.org/distrib/>
* Ubuntu should work, but less tested
* To just experiment can load a virtualbox image from: <https://www.osboxes.org/debian/> or <https://www.osboxes.org/ubuntu>.
These not need installation, password: `osboxes.org`

### Building the Raspiblitz scripts
* Run the build script in the terminal of the guest OS (with sudo access):

    ```
    # download the build script
    wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh
    # run
    sudo bash build_sdcard.sh -f true -b dev -d headless -t false -w off
    # Options:
    #   -h, --help                               this help info
    #   -i, --interaction [0|1]                  interaction before proceeding with exection (default: 1)
    #   -f, --fatpack [0|1]                      fatpack mode (default: 1)
    #   -u, --github-user [rootzoll|other]       github user to be checked from the repo (default: rootzoll)
    #   -b, --branch [v1.7|v1.8]                 branch to be built on (default: v1.7)
    #   -d, --display [lcd|hdmi|headless]        display class (default: lcd)
    #   -t, --tweak-boot-drive [0|1]             tweak boot drives (default: 1)
    #   -w, --wifi-region [off|US|GB|other]      wifi iso code (default: US) or 'off'
    ```

* Switch off when ready
* Attach an other disk (can be even small if you prune or [stop bitcoind](https://github.com/rootzoll/raspiblitz/issues/1500#issuecomment-982779830) manually.
The second virtual disk will be used as the BLOCKCHAIN drive.
This makes that data portable and independent from the OS similar to the combination of the SDcard and separate SSD.

### Notes:

#### Data drive:
* create a raw image of 500+ GB for best compatibility
* if there are permission issues try to symlink the disk image to `/var/lib/libvirt/images`

## Armbian
Many SBC-s are supported:
https://www.armbian.com/download/

To verify the downloaded image follow: https://docs.armbian.com/User-Guide_Getting-Started/#how-to-check-download-authenticity

Tested on:
* Odroid XU4 / HC1 / HC2 with the Armbian Buster image from https://www.armbian.com/odroid-xu4/

Burn the image to the SDcard with [Etcher](https://www.balena.io/etcher/).

Assemble and boot.

`ssh root@192.168.x.x`

password: `1234`

Follow the instructions in the terminal. Set the new password to `raspiblitz` and name the new user `admin` to keep in line with the rest of the setup.

Continue with building the SDcard: https://github.com/rootzoll/raspiblitz#build-the-sd-card-image

---

## Ubuntu
A common distro to be supplied by the manufacturer for various boards.

Tested on:
* Odroid XU4 with ubuntu-18.04.1-4.14-minimal image from https://de.eu.odroid.in/ubuntu_18.04lts/XU3_XU4_MC1_HC1_HC2
* Nvidia Jetson Nano with Ubuntu Bionic image from https://developer.nvidia.com/embedded/learn/get-started-jetson-nano-devkit#write

Burn the image to the SDCard with [Etcher](https://www.balena.io/etcher/).

Assemble and boot.

`ssh root@192.168.x.x`

password: odroid

`apt-get update`

`apt-get upgrade`

if there is an error:
>E: Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)

>E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?

run:
`reboot` and update as above

Continue with building the SDcard: https://github.com/rootzoll/raspiblitz#build-the-sd-card-image

---

## Python upgrade

```
# select version
pythonVersion="3.10.1"
majorPythonVersion=$(echo "$pythonVersion" | awk -F. '{print $1"."$2}' )
# update and upgrade
sudo apt update
sudo apt upgrade -y
# dependencies
sudo apt install wget software-properties-common build-essential libnss3-dev zlib1g-dev libgdbm-dev libncurses5-dev libssl-dev libffi-dev libreadline-dev libsqlite3-dev libbz2-dev -y
# download
wget https://www.python.org/ftp/python/${pythonVersion}/Python-${pythonVersion}.tgz
# optional signature for verification
wget https://www.python.org/ftp/python/${pythonVersion}/Python-${pythonVersion}.tgz.asc
# get PGP pubkey of Pablo Galindo Salgado
gpg --recv-key CFDCA245B1043CF2A5F97865FFE87404168BD847
# check for: Good signature from "Pablo Galindo Salgado <pablogsal@gmail.com>"
gpg --verify Python-${pythonVersion}.tgz.asc
# unzip
tar xvf Python-${pythonVersion}.tgz
cd Python-${pythonVersion}
# configure
./configure --enable-optimizations
# install
sudo make altinstall
# move the python binary to the expected directory
sudo mv $(which python${majorPythonVersion}) /usr/bin/
# check
ls -la /usr/bin/python${majorPythonVersion}
```

## Create an image release for amd64

Work notes partially based on: https://github.com/rootzoll/raspiblitz/blob/v1.7/FAQ.md#what-is-the-process-of-creating-a-new-sd-card-image-release

### Requirements:
* amd64 Laptop or Server
* [`Ubuntu Live`](https://releases.ubuntu.com/focal/ubuntu-20.04.4-desktop-amd64.iso) USB Stick to start on a clean system
* Installation medium: min 8GB SDcard / USB stick to install the base image from
* OS disk: min 32 GB Endurance type SDcard or USB SSD to run the opearting system on
* (Data disk: a new, minimum 1TB SSD is recommended - not needed to create the image release)
* [Tails USB Stick](https://tails.boum.org/install/download/) to sign the image offline
* PGP keys on an USB stick to sign the image
* NTFS formatted USB Stick or disk to store the signed image (can reuse the Installation medium)

### Create an NTFS formatted USB Stick / USB disk
* can be prepared any time on a separate computer and can reuse the Installation medium
* download the pishrink script to it:
```
curl https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh > pishrink.sh
```

### Boot Ubuntu Live from USB
* Start [`Ubuntu LIVE`](https://releases.ubuntu.com/focal/ubuntu-20.04.4-desktop-amd64.iso) from USB stick
* Under Settings: best to set correct keyboard language & power settings to prevent monitor turn off
****
### Download and verify the base image
* Download the latest [Debian Desktop netinst.io, SHA512SUMS and Signature](https://www.debian.org/download) and verify the [downloaded image](https://www.debian.org/CD/verify)
* In a terminal can use the following commands (see the comments for the explanations and an example output)
    ```bash
    # Download the base image:
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.3.0-amd64-netinst.iso
    # Download the SHA512SUMS:
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS
    # Download the Signature:
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS.sign

    # Verify:
    # download the signing pubkey:
    gpg --keyserver keyring.debian.org --receive-key DF9B9C49EAA9298432589D76DA87E80D6294BE9B
    # gpg: key DA87E80D6294BE9B: public key "Debian CD signing key <debian-cd@lists.debian.org>" imported
    # gpg: Total number processed: 1
    # gpg:               imported: 1
    # Verify the signature of the SHA512SUMS file
    gpg --verify gpg --verify SHA512SUMS.sign
    # Look for the output 'Good signature':
    # gpg: assuming signed data in 'SHA512SUMS'
    # gpg: Signature made Sat 26 Mar 2022 21:22:41 GMT
    # gpg:                using RSA key DF9B9C49EAA9298432589D76DA87E80D6294BE9B
    # gpg: Good signature from "Debian CD signing key <debian-cd@lists.debian.org>" [unknown]
    # gpg: WARNING: This key is not certified with a trusted signature!
    # gpg:          There is no indication that the signature belongs to the owner.
    # Primary key fingerprint: DF9B 9C49 EAA9 2984 3258  9D76 DA87 E80D 6294 BE9B

    # Compare the hash to the hash of the image file:
    sha512sum -c SHA512SUMS --ignore-missing
    # Look for the output 'OK':
    # debian-11.3.0-amd64-netinst.iso: OK
    ```
### Flash the base image to the installation medium
* Connect an SDcard reader with a 8GB SDcard or an USB stick.
* In the file manager open the context menu (right click) on the `netinst.iso` file.
* Select the option `Open With Disk Image Writer`.
* Write the image to the SDcard / USB SSD.

### Install Debian to the OS disk
* Connect the Laptop / Server to the network with the OS disk only, insert the installation medium and power up
* Continue to work on the screen of the laptop or a connected monitor
* Install Debian with the defaults - use a single partition for the OS
* During the setup create a new user called `pi`, set the password to `raspiblitz`

#### Install the RaspiBlitz Scripts
* once the setup is finished log in with the `pi` user
* Run the following command to build from the `dev` branch or `dev` with the branch-string of your version:
    ```
    wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh
    # run
    sudo bash build_sdcard.sh -f true -b dev -d headless -t false -w off
    ```
* Monitor/Check outputs for warnings/errors

#### Prepare the release
* switch to the admin user (pw: raspiblitz) and run the shortcut:
    ```
    release
    ```
* Disconnect WiFi/LAN on your laptop / server (hardware switch off) and shutdown
* Remove `Installation medium and the Ubuntu Live USB stick and cut power from the Laptop / Server
* Connect USB stick with latest `Tails` (make it stay offline)
* Boot Tails with extra setting of Admin-Password and remember (use later for sudo)
* Menu > Systemtools > Settings > Energy -> best to set monitor to never turn off
* Connect USB stick with GPG signing keys - decrypt drive if needed
* Open Terminal and cd into directory of USB Stick under `/media/amnesia`
* Run `gpg --import ./sub.key`, check and `exit`
* Disconnect USB stick with GPG keys

* Run `lsblk` to check on the built on the OS disk device name (ignore last partition number)
* Connect the NTFS USB stick, open in file manager and delete old files

* Clone the OS disk:
  ```bash
  dd if=/dev/[OSdiskddevice] | gzip > raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz
  ```

* When finished you should see that more than 7GB was copied.
* Create sha256 hash of the image:
    ```bash
    sha256sum *.gz > raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256
    ```
* Sign the sha256 hash file:
    ```bash
    gpg --detach-sign --armor *.sha256
    ```
* Check the files:
  ```bash
  ls
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256.asc
  ```
* Shutdown the build computer
* Upload the new image to server - put the .sig file and sha256sum.txt next to it
* Copy the sha256sum to GitHub README and update the download link

## Verify the downloaded the image
### Linux instructions
* Open a terminal in the directory with the downloaded files
    ```
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256
    raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256.asc
    ```
* Paste the following commands (see the comments for the explanations and an example output)
  ```bash
  # Import the signing pubkey:
  curl https://keybase.io/oms/pgp_keys.asc | gpg --import

  # Verify the signature of the sha256 hash:
  gpg --verify *.asc
  # Look for the output 'Good signature':
  # gpg: assuming signed data in 'raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz.sha256'
  # gpg: Signature made Mon DAY MONTH YEAR xx:xx:xx GMT
  # gpg:                using RSA key 13C688DB5B9C745DE4D2E4545BFB77609B081B65
  # gpg: Good signature from "openoms <oms@tuta.io>" [unknown]
  # gpg: WARNING: This key is not certified with a trusted signature!
  # gpg:          There is no indication that the signature belongs to the owner.
  # Primary key fingerprint: 13C6 88DB 5B9C 745D E4D2  E454 5BFB 7760 9B08 1B65

  # Compare the sha256 hash to the hash of the image file
  shasum -c *.sha256
  # Look for the output 'OK' :
  # raspiblitz-amd64-vX.X.X-YEAR-MONTH-DAY.img.gz: OK
  ```

## Create a torrent
* Create Torrent file from image (for example with Transmission) and place in in the `home.admin/assets` folder & link on README
* Tracker list recommended to be used with the torrent:
    ```
    udp://tracker.coppersurfer.tk:6969/announce
    http://tracker.yoshi210.com:6969/announce
    http://open.acgtracker.com:1096/announce
    http://tracker.skyts.net:6969/announce
    udp://9.rarbg.me:2780/announce
    http://tracker2.itzmx.com:6961/announce
    udp://exodus.desync.com:6969/announce
    http://pow7.com:80/announce
    udp://tracker.leechers-paradise.org:6969
    ```