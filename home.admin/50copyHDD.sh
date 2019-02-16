#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

# get local ip
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# additional prep if this is used to replace corrupted blockchain
if [ "${setupStep}" = "100" ]; then
  # warn user
  echo "!! Press ENTER to delete the old blockchain .. CTRL+C to CANCEL"
  read key
  # make sure services are not running
  echo "stopping servcies ..."
  sudo systemctl stop lnd 
  sudo systemctl stop bitcoind
  sudo systemctl disable bitcoind
  sudo cp -f /mnt/hdd/bitcoin/bitcoin.conf /home/admin/assets/bitcoin.conf 
fi

# delete all IN bitcoin directory but not itself if it exists
# so that possibel link to /home/bitcoin/.bitcoin nicht beschädigt wird
sudo rm -rfv /mnt/hdd/bitcoin/* 2>/dev/null

# make sure /mnt/hdd/bitcoin exists
sudo mkdir /mnt/hdd/bitcoin 2>/dev/null

# allow all users write to it ()
sudo chmod 777 /mnt/hdd/bitcoin

clear
echo "************************************************************************************"
echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from another computer"
echo "************************************************************************************"
echo ""
echo "You can use the blockchain from another bitcoin-core client with version greater or equal"
echo "to 0.17.1 with transaction index switched on (txindex=1 in the bitcoin.conf)."
echo ""
echo "Both computers (your RaspberryPi and the other computer with the full blockchain on) need"
echo "to be connected to the same local network."
echo ""
echo "Open a terminal on the source computer and change into the directory that contains the"
echo "blockchain data. You should see directories 'blocks', 'chainstate' & 'indexes'".
echo "Make sure the bitcoin client on that computer is stopped."
echo ""
echo "COPY, PASTE & EXECUTE the following command on the blockchain source computer:"
echo "sudo scp -r ./chainstate ./indexes ./testnet3 ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
echo "" 
echo "This command may ask you first about the admin password of the other computer (because sudo)."
echo "Then it will ask for your SSH PASSWORD A from this RaspiBlitz."
echo "It can take multiple hours until transfer is complete - be patient."
echo "************************************************************************************"
echo "PRESS ENTER if transfers is done OR if you want to choose another another option."
sleep 2
read key

# make quick check if data is there
anyDataAtAll=0
quickCheckOK=1
count=$(sudo ls /mnt/hdd/bitcoin/blocks 2>/dev/null | grep -c '.dat')
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/blocks"
   anyDataAtAll=1
fi
if [ ${count} -lt 3000 ]; then
  echo "FAIL: transfere seems invalid - less then 3000 .dat files (${count})"
  quickCheckOK=0
fi
count=$(sudo ls /mnt/hdd/bitcoin/chainstate 2>/dev/null | grep -c '.ldb')
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/chainstate"
   anyDataAtAll=1
fi
if [ ${count} -lt 1400 ]; then
  echo "FAIL: transfere seems invalid - less then 1400 .ldb files (${count})"
  quickCheckOK=0
fi
count=$(sudo ls /mnt/hdd/bitcoin/indexes/txindex 2>/dev/null | grep -c '.ldb')
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/indexes/txindex"
   anyDataAtAll=1
fi
if [ ${count} -lt 1500 ]; then
  echo "FAIL: less then 1500 .ldb files (${count}) in /mnt/hdd/bitcoin/indexes/txindex (transfere seems invalid)"
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

  fi

else

  echo "CANCEL -> NO DATA was copied."
  quickCheckOK=0

fi
echo "*********************************************"

# if started after intial setup - quit here
if [ "${setupStep}" = "100" ]; then
  sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
  sudo chown bitcoin:bitcoin /mnt/hdd/bitcoin/bitcoin.conf
  sudo systemctl enable bitcoind
  echo "DONE - reboot is needed: sudo shutdown -r now"
  exit 0
fi

# REACT ON QUICK CHECK DURING INITAL SETUP


if [ ${quickCheckOK} -eq 0 ]; then

  echo "*********************************************"
  echo "There seems to be an invalid transfer."

  echo "Wait 5 secs ..."
  sleep 5
  dialog --title " INVALID TRANSFER - DELETE DATA?" --yesno "Quickcheck shows the data you transferred is invalid/incomplete. This can lead further RaspiBlitz setup to get stuck in error state.\nDo you want to reset/delete data data?" 8 60
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
