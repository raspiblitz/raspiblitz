#!/bin/bash

# Display a QR code for the string in qr.txt

echo
echo "Please wait. Generating QR-code..."
echo 
# make sure qrcode-encode and fbi are installed
sudo apt-get install qrencode fbi -y > /dev/null

qrencode -l L -o /home/admin/qr.png < /home/admin/qr.txt > /dev/null
sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/qr.png 2> /dev/null

echo "************************************"
echo "Scan the QR-Code on the LCD-Display."
echo "************************************"
echo
echo "If you don't have access to the LCD, you can view it here."
echo "Make the this terminal window as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to show QR code."

read key

clear
qrencode -t ANSI256 < /home/admin/qr.txt
shred /home/admin/qr.txt
rm -f /home/admin/qr.txt
echo "(To shrink QR code: macOS press CMD- / LINUX press CTRL-) Press ENTER when finished."
read key

clear

# remove the QR picture on the raspi LCD
sudo killall -3 fbi
shred /home/admin/qr.png
rm -f /home/admin/qr.png
