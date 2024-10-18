#!/bin/bash -eux

# Apt cleanup.
apt autoremove
apt update

# Delete unneeded files.
rm -f /home/vagrant/*.sh
rm /home/vagrant/VBoxGuestAdditions.iso

# Add `sync` so Packer doesn't quit too early, before the large file is deleted.
sync
