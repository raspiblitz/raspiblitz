# ⚡️ Alternative platforms for the RaspiBlitz ⚡️

Minimum requirements:
* ARMv8 or x86 processor (64 bit)
* 1 GB RAM
* 500 GB HDD

Desirable:
* \> 2GB DDR3 ECC RAM (8GB+ if using ZFS)
* USB 3.0 / SATA / PCIE / NVME connectors
* SSD - multiple disks for redundancy

Specifications of the tested hardware: [hw_comparison.md](hw_comparison.md)

All testers are welcome. Open an issue for your specific board to collaborate and share your experience.

---
## Virtual Machine
Tested with: 
* Ubuntu image in VirtualBox and linux virt-manager / [cockpit-machines](https://github.com/cockpit-project/cockpit-machines)
* Debian image in VirtualBox https://github.com/rootzoll/raspiblitz/issues/2756#issuecomment-983532237
* TrueNAS (FreeBSD bhyve) with an Ubuntu VM: https://github.com/rootzoll/raspiblitz/issues/2104#issuecomment-917444238

To just experiment can load a virtualbox image from: https://www.osboxes.org/ubuntu (does not need installation)
Password: `osboxes.org`
Can carry on straight to building the OS:

```
# download the build script
wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh
# run
sudo bash build_sdcard.sh false false rootzoll dev headless
```

switch off when ready   
and attach an other disk (can be even small if you prune or [stop bitcoind](https://github.com/rootzoll/raspiblitz/issues/1500#issuecomment-982779830) ).

The second virtual disk will be used as the BLOCKCHAIN drive.  
This makes that data portable and independent from the OS similar to the combination of the SDcard and separate SSD.

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

password: 1234

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

## DietPi

Many SBC-s are supported:
https://dietpi.com/#download

Tested on:

* Odroid HC1
* Odroid HC2 (the same board with a 3.5" 12V HDD)
* Odroid XU4 (with HDMI screen)
* Raspberry Pi 3 B+ (with the default GPIO or HDMI display)


The HDMI screen tested: https://www.aliexpress.com/item/3-5-inch-LCD-HDMI-USB-Touch-Screen-Real-HD-1920x1080-LCD-Display-Py-for-Raspberri/32818537950.html

Detailed instructions for the RaspiBlitz-on-DietPi: [alternative.platforms/dietpi/README.md](/alternative.platforms/dietpi/README.md)

---

For the process to build a custom SDcard image release see:
https://github.com/rootzoll/raspiblitz/blob/dev/FAQ.md#what-is-the-process-of-creating-a-new-sd-card-image-release

Extras for advanced users and powerful hardware:
https://github.com/openoms/bitcoin-tutorials/