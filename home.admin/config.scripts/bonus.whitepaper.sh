#!/bin/bash

WhitepaperVersion="v0.1"
DownloadPath="/home/admin"
WhitepaperFilename="/bitcoin.pdf"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to download the Bitcoin whitepaper to your Raspiblitz directly from the blockchain"
  echo "# on: downloads the Whitepaper to $DownloadPath$WhitepaperFilename"
  echo "# off: deletes the Whitepaper from $DownloadPath$WhitepaperFilename"
  echo "# bonus.whitepaper.sh [on|off|menu]"
  echo "# Whitepaper downloader script $WhitepaperVersion"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Whitepaper Info" --msgbox "
This service downloads Satoshi's Whitepaper directly from the blockchain.
When enabled, the Whitepaper is downloaded to $DownloadPath$WhitepaperFilename
When disabled, the Whitepaper is deleted from $DownloadPath$WhitepaperFilename
Also, use the command 'whitepaper' from the command line to download the whitepaper directly.
From the user home folder, call an editor 'nano bitcoin.pdf' to enter the bitcoin.txt or use 'less bitcoin.txt' command, both to view the file in ASCII format.
" 13 78
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
    echo ""
    echo "# ***"
    echo "# Downloading the Whitepaper to $DownloadPath$WhitepaperFilename..."
    echo "# ***"
    echo ""
    # download from blockchain and transform into pdf
    sudo -u bitcoin bitcoin-cli getblock 00000000000000ecbbff6bafb7efa2f7df05b227d5c73dca8f2635af32a2e949 0 |\
    tail -c+92167 |\
    for ((o=0;o<946;++o)) ; do read -rN420 x ; echo -n ${x::130}${x:132:130}${x:264:130} ; done |\
    xxd -r -p |\
    tail -c+9 |\
    head -c184292 > $DownloadPath/$WhitepaperFilename
    # transfor pdf to txt to view with less through the terminal
    pdftotext $DownloadPath$WhitepaperFilename
    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set whitepaper "on"
    echo "# OK - Whitepaper downloaded to $DownloadPath$WhitepaperFilename"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=1
  if [ ${isInstalled} -eq 1 ]; then
    echo ""
    echo "# ***"
    echo "# Removing the Whitepaper from $DownloadPath$WhitepaperFilename..."
    echo "# ***"
    echo ""
    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set whitepaper "off"
    rm $DownloadPath$WhitepaperFilename
    rm $DownloadPath/bitcoin.txt
    echo "# OK - Whitepaper removed."
  else
    echo "# The Whitepaper has not been downloaded yet."
  fi
  exit 0
fi
