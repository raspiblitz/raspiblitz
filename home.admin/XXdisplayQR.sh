#!/bin/bash

# Display a QR code for the string in qr.txt

# make sure qrcode-encode and fbi are installed
#clear
#echo "*** Setup ***"

echo 50 | whiptail --title "Installing" --backtitle "QR-Code" --gauge "please wait" 4 40 100
./XXaptInstall.sh qrencode
echo 90 | whiptail --title "Installing" --backtitle "QR-Code" --gauge "please wait" 4 40 100
./XXaptInstall.sh fbi

whiptail --title "Get ready" --backtitle "QR-Code in Terminal Window" \
       --msgbox "Make this terminal window as large as possible - fullscreen would be best. \n\nThe QR-Code might be too large for your display. In that case, shrink the letters by pressing the keys Ctrl and Minus (or Cmd and Minus if you are on a Mac) \n\nPRESS ENTER when you are ready to see the QR-code." 20 60

clear
qrencode -t ANSI256 < /home/admin/qr.txt
shred /home/admin/qr.txt
rm -f /home/admin/qr.txt
echo "(To shrink QR code: macOS press CMD- / LINUX press CTRL-) Press ENTER when finished."
read key

clear
