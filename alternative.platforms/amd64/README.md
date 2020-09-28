# ⚡️ RaspiBlitz-on-amd64 ⚡️

This guide was tested on vagrant

---

This feature is very experimental and not supported.

In order to run raspiblitz on `vagrant` you need `packer` to build the base box.

```sha
cd alternative.platforms/amd64/packer
packer build raspiblitz.json

vagrant box add --force raspiblitz output/raspiblitz.box
cd ../../..
```

With the base box built, you can start a development environment with `vagrant up` and login with `vagrant ssh`.


**Note**

Every file in `home.admin` will be linked to `/home/admin` inside the VM,
if you add a new file you should run `vagrant provision` to make sure it gets linked inside the VM. Every time you boot the VM, `home.admin` files will be linked automatically.

The content of the `/home/admin/assets` folder is not kept in sync at the moment (see [#1578](https://github.com/rootzoll/raspiblitz/issues/1578)). You can still access your development assets file inside the VM in `/vagrant/home.admin/assets/`.
