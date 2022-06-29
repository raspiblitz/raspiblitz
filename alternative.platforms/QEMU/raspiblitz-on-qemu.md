Documentation focused on install for dev environment with macos. Do not rely on this setup for nodes on mainnet. 

1. Download [Debian 10.4 Minimal Image](https://mac.getutm.app/gallery/debian-10-4-minimal)
2. Resize the image container to 30GB
	`qemu-img resize ~/Library/Containers/com.utmapp.UTM/Data/Documents/Debian\ ARM.utm/Images/debian.qcow2 +30G`
3. Add USB Device to the VM
	- Right click the VM from the list.
	- Select `new drive` from the Drives Menu
	- Update the interface to `USB`
	- Update size to 40GB
4. Install Dependencies
	- `sudo apt install mount e2fsprogs gnupg2`
	- Install [armbian-config](https://github.com/armbian/config#armbian-configuration-utility)
		```
		echo "deb [arch=arm64] http://apt.armbian.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/armbian.list
		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 9F0E78D5
		sudo apt update
		sudo apt install armbian-config
		```
5. (Optional) Switch to swapfile - [Reference](https://www.linuxuprising.com/2018/08/how-to-use-swap-file-instead-of-swap.html)	
	```
	sudo swapoff /dev/vda3
	sudo vim /etc/fstab 
	sudo dd if=/dev/zero of=/swapfile bs=1024 count=1048576`
	sudo chmod 600 /swapfile 
	sudo mkswap /swapfile
	sudo swapon /swapfile
	swapon -s
	```
6. Update `/etc/apt/sources` to `bullseye` and add `raspi.list`
	```
	deb https://archive.raspberrypi.org/debian/ bullseye main
	deb-src https://archive.raspberrypi.org/debian/ bullseye main
	```
	- [https://ict.gctaa.net/resources/adding_raspbian_repo.html](https://ict.gctaa.net/resources/adding_raspbian_repo.html)
	- [https://www.linuxquestions.org/questions/blog/craigevil-176422/raspberry-pi-os-debian-11-bullseye-apt-repos-38636/](https://www.linuxquestions.org/questions/blog/craigevil-176422/raspberry-pi-os-debian-11-bullseye-apt-repos-38636/)
	- [https://www.cyberciti.biz/faq/update-upgrade-debian-10-to-debian-11-bullseye/](https://www.cyberciti.biz/faq/update-upgrade-debian-10-to-debian-11-bullseye/)
	- [https://www.tomshardware.com/how-to/upgrade-raspberry-pi-os-to-bullseye-from-buster](https://www.tomshardware.com/how-to/upgrade-raspberry-pi-os-to-bullseye-from-buster)
7. Add /usr/sbin to path
   1. `sudo vim ~/.bashrc`
   2. Add `PATH=$PATH:/usr/sbin` to the end of the file
   3. Save File `:wq!`
   4. Run `source ~/.bashrc`

8.  Add keys 
	```
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E
	sudo apt-key adv --recv-keys --keyserver **keys.openpgp.org** 74A941BA219EC810
	```
9. Resize partition - [Source](https://askubuntu.com/a/116367)
	1. Run `sudo fdisk /dev/sda`
	    - use `p` to list the partitions. Make note of the start cylinder of `/dev/sda1`
	    - use `d` to **delete** first the swap partition (`2`) and then the `/dev/sda1` partition. This is very scary but is actually harmless as the data is not written to the disk until you write the changes to the disk.
	    - use `n` to **create** a new primary partition. Make sure its start cylinder is exactly the same as the old `/dev/sda1` used to have. For the end cylinder agree with the default choice, which is to make the partition to span the whole disk.
	    - review your changes, make a deep breath and use `w` to write the new partition table to disk. 
	2. Reboot with `sudo reboot`.
10. Make usb  filesystem  by running command  `mkfs.ext4 /dev/sda1` where `/dev/sda1` is your new disk.
11. [Install raspiblitz via build script](https://github.com/rootzoll/raspiblitz/tree/v1.7/alternative.platforms#building-the-raspiblitz-scripts)
12. [Configure signet](https://github.com/rootzoll/raspiblitz/issues/1500#issuecomment-982779830)
13. Reboot with `sudo reboot`.
14. Login with `admin` user.  Default password: `raspiblitz`