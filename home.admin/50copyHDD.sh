#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null

# get local ip
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# create bitcoin base directory and link with bitcoin user
sudo mkdir /mnt/hdd/bitcoin
sudo chown bitcoin:bitcoin /mnt/hdd/bitcoin
sudo ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin

echo ""
echo "*** Instructions to COPY BLOCKCHAIN from another computer (only MAINNET) ***"
echo ""
echo "You can use the blockchain from another bitcoin-core client with version greater or equal"
echo "to 0.17.1 with transaction index switched on (`txindex=1` in the `bitcoin.conf`)."
echo ""
echo "Both computers (your RaspberryPi and the other computer with the full blockchain on) need"
echo "to be connected to the same local network."
echo ""
echo "Open a terminal on the other computer and change into the directory that constains the"
echo "blockchain data. You should see directories 'blocks', 'chainstate' & 'indexes'".
echo "Make sure the bitcoin client on that computer is stopped."
echo ""
echo "Copy, Paste and Execute the following commands - line by line:"
echo "sudo scp -R ./chainstate bitcoin@${localip}:/home/bitcoin/.bitcoin/chainstate"
echo "sudo scp -R ./indexes bitcoin@${localip}:/home/bitcoin/.bitcoin/indexes"
echo "sudo scp -R ./blocks bitcoin@${localip}:/home/bitcoin/.bitcoin/blocks"
echo ""
echo "Every command above needs your SSH PASSWORD A to work and will take some time to transfer."
echo "PRESS ENTER if all 3 transfers are done or if you dont care and you want to return to menu."
read key

# unlink bitcoin user (will created later in setup again)
sudo unlink /home/bitcoin/.bitcoin 

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
if [ ${count} -lt 5200 ]; then
  echo "FAIL: less then 5200 .ldb files (${count}) in /mnt/hdd/bitcoin/chainstate (transfere seems invalid)"
  quickCheckOK=0
fi

# just if any data transferred ..
if [ ${anyDataAtAll} -eq 1 ]; then

  # data was invalkid - ask user to keep?
  if [ ${quickCheckOK} -eq 0 ]; then
    echo "*********************************************"
    echo "There seems to be a invalid transfere."
    echo "Wait 5 secs ..."
    sleep 5
    dialog --title " INVALID TRANSFER" --yesno "Quickcheck shows the data you transferred is invalid/incomplete.\nThis can lead further RaspiBlitz setup to get stuck in error state.\nDo you want to reset/delete data data?" 8 57
    response=$?
    echo "response(${response})"
    case $response in
      0) quickCheckOK=1 ;;
    esac
  fi

  if [ ${quickCheckOK} -eq 0 ]; then
    echo "Deleting invalid Data ..."
    sudo rm -rf /mnt/hdd/bitcoin
    sudo rm -rf /home/bitcoin/.bitcoin
    sleep 2
  fi

else
  
  # when no data transferred - just delete bitcoin base dir again
  sudo rm -rf /mnt/hdd/bitcoin

fi

# setup script will decide the next logical step
./10setupBlitz.sh