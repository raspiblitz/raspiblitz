# Packer build notes

Workflow on github and locally tested on Debian to generate a .qcow2 format amd64 image.
Works when mounted with libvirt / virsh / virt-manager (https://virt-manager.org/) and also when written to disk with legacy boot (non-UEFI).

Issue: https://github.com/rootzoll/raspiblitz/issues/3053
Templates are sourced from: https://github.com/chef/bento

## Local build
with the [Makefile](https://github.com/openoms/raspiblitz/blob/ci-amd64/Makefile) (needs ~10 GB free space):
```
git clone https://github.com/openoms/raspiblitz
cd raspiblitz
git checkout add-amd64-image-build
make amd64-lean-image
```

## Images generated in github actions
Find the images in the green runs in github actions at:
https://github.com/openoms/raspiblitz/actions

The images are built using the dev branch.

## Write the image to a disk connected with USB
identify the connected disk with `lsblk` eg `/dev/sdd`
```
gzip -dkv debian-11.5-amd64-lean.qcow2.gz
sudo qemu-img dd bs=4M if=debian-11.5-amd64-lean.qcow2  of=/dev/sdd
```
## Convert qcow2 to raw image
warning the raw lean image is 32 GB
```
gzip -dkv debian-11.5-amd64-lean.qcow2.gz
qemu-img convert debian-11.5-amd64-lean.qcow2 debian-11.5-amd64-lean.img
```
and write to a disk connected with USB with Balena Etcher or `dd`.

## Extend the partition on the new disk
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

## Getting started
press CTRL+D to get to a login prompt
username: `admin`
password: `raspiblitz`

## Add Gnome desktop
connect to the internet (easiest to plug in a LAN cable - use a USB - LAN adapter if have no port)
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