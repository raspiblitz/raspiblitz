#!/bin/bash

# Display a QR code for the string in qr.txt

# make sure qrcode-encode and fbi are installed
./XXaptInstall.sh qrencode
./XXaptInstall.sh fbi

qrencode -l L -o /home/admin/qr.png < /home/admin/qr.txt > /dev/null
sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/qr.png 2> /dev/null
