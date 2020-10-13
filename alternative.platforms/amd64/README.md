# ⚡️ RaspiBlitz-on-amd64 ⚡️

This guide was tested on vagrant

---

This feature is very experimental and not supported.

In order to run raspiblitz on `vagrant` you need `packer` (>=1.6.0) to build the base box.

On MacOS you need to install:
1. brew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"`
2. packer: `brew install packer`
3. vagrant: `brew install vagrant`
4. virtualbox: `brew cask install virtualbox` (maybe re-run after you changed the requested secruity permission to be successfull)

```sha
cd alternative.platforms/amd64/packer
packer build raspiblitz.json

vagrant box add --force raspiblitz output/raspiblitz.box
cd ../../..
```

With the base box built, you can start a development environment with `vagrant up` and login with `vagrant ssh`.

You will need to connect a virtual data drive to the RaspiBlitzVM ... todo so:
- make sure VM is stopped: use command `off` when within VM or from outside `vagrant halt`
- no open the VirtualBox Manager GUI and use `change` on the RaspiBlitzVM
- Go to the `mass storage` section and add a second disc as `primary slave` to the already existing controller
- create a new dynamic VDI with around 900GB .. choose as storage path for the VDI an external drive if you dont have that much space on your laptop.
- now start the VM again with `vagrant up` and `vagrangt ssh` to run thru the setup process

**Note**

Every file in `home.admin` will be linked to `/home/admin` inside the VM,
if you add a new file you should run `vagrant provision` to make sure it gets linked inside the VM. Every time you boot the VM, `home.admin` files will be linked automatically.

The content of the `/home/admin/assets` folder is not kept in sync at the moment (see [#1578](https://github.com/rootzoll/raspiblitz/issues/1578)). You can still access your development assets file inside the VM in `/vagrant/home.admin/assets/`.
