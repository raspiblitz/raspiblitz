#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

# get local ip
localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# Basic Options
OPTIONS=(WINDOWS "Windows" \
         MACOS "Apple MacOSX" \
         LINUX "Linux" \
         BLITZ "RaspiBlitz"
        )

CHOICE=$(dialog --clear --title " Copy Blockchain from another laptop/node over LAN " --menu "\nWhich system is running on the other laptop/node you want to copy the blockchain from?\n " 14 60 9 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
        MACOS) echo "Steve";;
        LINUX) echo "Linus";;
        WINDOWS) echo "Bill";;
        BLITZ) echo "Satoshi";;
        *) exit 1;;
esac

# additional prep if this is used to replace corrupted blockchain
if [ "${setupStep}" = "100" ]; then
  # make sure services are not running
  echo "stopping services ..."
  sudo systemctl stop lnd 
  sudo systemctl stop bitcoind
  sudo cp -f /mnt/hdd/bitcoin/bitcoin.conf /home/admin/assets/bitcoin.conf 
fi

# check if old blockchain data exists
hasOldBlockchainData=0
sizeBlocks=$(sudo du -s /mnt/hdd/bitcoin/blocks 2>/dev/null | tr -dc '[0-9]')
if [ ${#sizeBlocks} -gt 0 ] && [ ${sizeBlocks} -gt 0 ]; then
  hasOldBlockchainData=1
fi
sizeChainstate=$(sudo du -s /mnt/hdd/bitcoin/chainstate 2>/dev/null | tr -dc '[0-9]')
if [ ${#sizeChainstate} -gt 0 ] && [ ${sizeChainstate} -gt 0 ]; then
  hasOldBlockchainData=1
fi

if [ ${hasOldBlockchainData} -eq 1 ] && [ "$1" != "stop-after-script" ]; then
  dialog --title " Old Blockchain Data Found " --yesno "\nDo you want to delete the old/local blockchain data now?" 7 60
  response=$?
  echo "response(${response})"
  if [ "${response}" = "1" ]; then
    echo "OK - keep old blockchain - just try to repair by copying over it"
    sleep 3
  else
    echo "OK - delete old blockchain"
    sudo rm -rfv /mnt/hdd/bitcoin/blocks/* 2>/dev/null
    sudo rm -rfv /mnt/hdd/bitcoin/chainstate/* 2>/dev/null
    sleep 3
  fi
fi

# make sure /mnt/hdd/bitcoin exists
sudo mkdir /mnt/hdd/bitcoin 2>/dev/null

# allow all users write to it
sudo chmod 777 /mnt/hdd/bitcoin

echo 
clear
if [ "${CHOICE}" = "WINDOWS" ]; then
  echo "****************************************************************************"
  echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a WINDOWS computer"
  echo "****************************************************************************"
  echo ""
  echo "ON YOUR WINDOWS COMPUTER download and validate the blockchain with the Bitcoin"
  echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
  echo "If the Bitcoin Blockchain is synced up - make sure that your Windows computer &"
  echo "your RaspiBlitz are in the same local network."
  echo ""
  echo "Open a fresh terminal on your Windows computer & change into the directory that"
  echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
  echo "there. Normally on Windows thats: C:\Users\YourUserName\Appdata\Roaming\Bitcoin"
  echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
  echo ""
  echo "COPY, PASTE & EXECUTE the following command on your Windows computer terminal:"
  echo "scp -r ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
  echo ""
  echo "If asked for a password use PASSWORD A (or 'raspiblitz')."
fi
if [ "${CHOICE}" = "MACOS" ]; then
  echo "****************************************************************************"
  echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a MacOSX computer"
  echo "****************************************************************************"
  echo ""
  echo "ON YOUR MacOSX COMPUTER download and validate the blockchain with the Bitcoin"
  echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
  echo "If the Bitcoin Blockchain is synced up - make sure that your MacOSX computer &"
  echo "your RaspiBlitz are in the same local network."
  echo ""
  echo "Open a fresh terminal on your MacOSX computer and change into the directory that"
  echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
  echo "there. Normally on MacOSX thats: cd ~/Library/Application Support/Bitcoin/"
  echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
  echo ""
  echo "COPY, PASTE & EXECUTE the following command on your MacOSX terminal:"
  echo "sudo rsync -avhW --progress ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
  echo ""
  echo "You will be asked for passwords. First can be the user password of your MacOSX"
  echo "computer and the last is the PASSWORD A (or 'raspiblitz') of this RaspiBlitz."
fi
if [ "${CHOICE}" = "LINUX" ]; then
  echo "****************************************************************************"
  echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a LINUX computer"
  echo "****************************************************************************"
  echo ""
  echo "ON YOUR LINUX COMPUTER download and validate the blockchain with the Bitcoin"
  echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
  echo "If the Bitcoin Blockchain is synced up - make sure that your Linux computer &"
  echo "your RaspiBlitz are in the same local network."
  echo ""
  echo "Open a fresh terminal on your Linux computer and change into the directory that"
  echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
  echo "there. Normally on Linux thats: cd ~/.bitcoin/"
  echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
  echo ""
  echo "COPY, PASTE & EXECUTE the following command on your Linux terminal:"
  echo "sudo rsync -avhW --progress ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
  echo ""
  echo "You will be asked for passwords. First can be the user password of your Linux"
  echo "computer and the last is the PASSWORD A (or 'raspiblitz') of this RaspiBlitz."
fi
if [ "${CHOICE}" = "BLITZ" ]; then
  echo "****************************************************************************"
  echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from another RaspiBlitz"
  echo "****************************************************************************"
  echo ""
  echo "The other RaspiBlitz needs a minimum version of 1.6 (if lower, update first)."
  echo "Make sure that the other RaspiBlitz is on the same local network."
  echo ""
  echo "Open a fresh terminal and login per SSH into that other RaspiBlitz."
  echo "Once in the main menu go: MAINMENU > REPAIR > COPY-SOURCE"
  echo "Follow the given instructions ..."
  echo ""
  echo "The LOCAL IP of this target RaspiBlitz is: ${localip}"
fi
echo "" 
echo "It can take multiple hours until transfer is complete - be patient."
echo "****************************************************************************"
echo "PRESS ENTER if transfers is done OR if you want to choose another option."
sleep 2
read key

# make quick check if data is there
anyDataAtAll=0
quickCheckOK=1
count=$(sudo find /mnt/hdd/bitcoin/ -iname *.dat -type f | wc -l)
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/blocks"
   anyDataAtAll=1
fi
if [ ${count} -lt 300 ]; then
  echo "FAIL: transfer seems invalid - less then 300 .dat files (${count})"
  quickCheckOK=0
fi
count=$(sudo find /mnt/hdd/bitcoin/ -iname *.ldb -type f | wc -l)
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/chainstate"
   anyDataAtAll=1
fi
if [ ${count} -lt 700 ]; then
  echo "FAIL: transfer seems invalid - less then 700 .ldb files (${count})"
  quickCheckOK=0
fi

echo "*********************************************"
echo "QUICK CHECK RESULT"
echo "*********************************************"

# just if any data transferred ..
if [ ${anyDataAtAll} -eq 1 ]; then

  # data was invalid - ask user to keep?
  if [ ${quickCheckOK} -eq 0 ]; then

    echo "FAIL -> DATA seems incomplete."

  else

    echo "OK -> DATA LOOKS GOOD :D"
    sudo rm /mnt/hdd/bitcoin/debug.log 2>/dev/null

  fi

else

  echo "CANCEL -> NO DATA was copied."
  quickCheckOK=0

fi
echo "*********************************************"

# if started with parameter "stop-after-script" - quit here
if [ "$1" == "stop-after-script" ]; then
  if [ ${quickCheckOK} -eq 0 ]; then
    echo "cleaning up .."
    sudo rm -rf /mnt/hdd/bitcoin/blocks
    sudo rm -rf /mnt/hdd/bitcoin/chainstate
  fi
  echo "DONE Copy"
  exit 0
fi

# if started after intial setup - quit here
if [ "${setupStep}" = "100" ]; then
  sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
  rpcpass=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep 'bitcoind.rpcpass' | cut -d "=" -f2)
  sudo chown bitcoin:bitcoin /mnt/hdd/bitcoin/bitcoin.conf
  sudo sed -i "s/^rpcpassword=.*/rpcpassword=${rpcpass}/g" /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null
  sudo systemctl enable bitcoind
  echo "DONE - rebooting: sudo shutdown -r now"
  sudo shutdown -r now
  exit 0
fi

# REACT ON QUICK CHECK DURING INITAL SETUP

if [ ${quickCheckOK} -eq 0 ]; then

  echo "*********************************************"
  echo "There seems to be an invalid transfer."

  echo "Wait 5 secs ..."
  sleep 5
  dialog --title " INVALID TRANSFER - DELETE DATA?" --yesno "Quickcheck shows the data you transferred is invalid/incomplete. This can lead further RaspiBlitz setup to get stuck in error state.\nDo you want to reset/delete data?" 8 60
  response=$?
  echo "response(${response})"
  case $response in
    1) quickCheckOK=1 ;;
  esac
  
fi

if [ ${quickCheckOK} -eq 0 ]; then
  echo "Deleting invalid Data ... "
  sudo rm -rf /mnt/hdd/bitcoin
  sleep 2
fi

# setup script will decide the next logical step
/home/admin/10setupBlitz.sh
