# Automated builds

The workflow on github and locally generates a .qcow2 format amd64 image.
Works when mounted with libvirt / virsh / virt-manager (https://virt-manager.org/) and also when written to disk with legacy boot (non-UEFI).

Issue: https://github.com/rootzoll/raspiblitz/issues/3053

Templates are sourced from: https://github.com/chef/bento

The lean image has no Gnome desktop or WebUI installed.

## Local build
with the [Makefile](https://github.com/openoms/raspiblitz/blob/ci-amd64/Makefile)
* needs ~10 GB free space
* tested on:
  * Debian Bullseye Desktop
  * Ubuntu Live
* build process:
    ```
    git clone https://github.com/openoms/raspiblitz
    cd raspiblitz
    git checkout add-amd64-image-build
    make amd64-fatpack-image
    ```

## Images generated in github actions
Find the images in the green runs in github actions at:
https://github.com/openoms/raspiblitz/actions

The images are built using the dev branch.

## Write the image to a disk connected with USB
identify the connected disk with `lsblk` eg `/dev/sdd`

###  Convert qcow2 to raw image
* the raw image is 33.5 GB
    ```
    gzip -dkv debian-11.5-amd64-fatpack.qcow2.gz
    qemu-img convert debian-11.5-amd64-fatpack.qcow2 debian-11.5-amd64-fatpack.img
    ```
### Write to a disk connected with USB with Balena Etcher or `dd`

### Extend the partition on the new disk (optional)
* Use Disks to resize the Extended Partition to the full size of the disk
* To extend the LVM:
    ```
    # identify the USB connected disk
    lsblk
    # download the script
    git clone https://git.scs.carleton.ca/git/extend-lvm.git
    # run with the disk as the parameter (sde for example)
    sudo bash extend-lvm/extend-lvm.sh /dev/sde
    ```

## The first boot
### fatpack image
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

#### Add Gnome desktop (optional)
* Connect to the internet (easiest to plug in a LAN cable - use a USB - LAN adapter if have no port)
    ```
    sudo apt install gnome
    sudo systemctl start gdm
    ```

## Workflow notes
* Packer .json settings:
    * `disk_size` - the size op the raw image. The .qcow2 file is compressed.
    * `template`  - image filename
    * `output_directory` - directory under builds where the image will be placed
    * the `pi` user is given passwordless sudo access and used for the image setup
* VNC
    * can follow the setup locally in VNC with the port stated in the first part of the logs
* Flashing
    * using `sudo qemu-img dd bs=4M if=debian-11.5-amd64-lean.qcow2 of=/dev/sdd` changed the UUID so it won't boot without editing the GRUB
