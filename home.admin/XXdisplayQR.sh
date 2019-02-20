#!/bin/bash

# Display a QR code provided as parameter $1

qrcode=$1

# make sure qrcode-encoder in installed
clear
echo "*** Setup ***"
sudo apt-get install qrencode -y 

clear
echo "Make the this terminal as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to generare the QR code and scan it with the app."
read key

clear
echo -e "$1" |  qrencode -t ANSI256
echo -e "$1"
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
read key

clear
