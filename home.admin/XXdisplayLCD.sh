#!/bin/bash

# Display an image on the LCD

# make sure fbi is installed
./XXaptInstall.sh fbi

sudo fbi -a -T 1 -d /dev/fb1 --noverbose $1 2> /dev/null
