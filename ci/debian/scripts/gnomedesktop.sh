#!/bin/sh -eux

echo 'Add Gnome desktop'
export DEBIAN_FRONTEND=none
sudo apt install gnome -y
