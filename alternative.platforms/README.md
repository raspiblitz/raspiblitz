# ⚡️ Alternative platforms for the RaspiBlitz ⚡️

Minimum requirements:
* ARMv8 or x86 processor (64 bit)
* 1 GB RAM
* 500 GB HDD
* Python >=3.9 (see [how to upgrade below](#python-upgrade) )

Desirable:
* \> 2GB DDR3 ECC RAM (8GB+ if using ZFS)
* USB 3.0 / SATA / PCIE / NVME connectors
* SSD - multiple disks for redundancy

Specifications of the tested hardware: [hw_comparison.md](hw_comparison.md)

All testers are welcome. Open an issue for your specific board to collaborate and share your experience.

---
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

#### Mount a raw disk image on the host system to copy blockchain
* this is not necessary, but faster than to copy over the network
* from <https://support.hpe.com/hpesc/public/docDisplay?docId=emr_na-c02814204>

    ```
    losetup /dev/loop0 VirtualMachineImage.raw
    sudo apt install kpartx -y  
    kpartx -a /dev/loop0
    sudo mkdir /mnt/rawdisk
    mount /dev/mapper/loop0p1 /mnt/rawdisk
    ```
* the guest data-drive will be available in `/mnt/rawdisk`
---
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