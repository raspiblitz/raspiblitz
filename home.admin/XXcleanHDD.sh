#!/bin/bash
echo ""
extraParameter="$1"
forceParameter="$2"
if [ "${extraParameter}" = "-all" ]; then

    echo "!!!! This will DELETE ALL DATA & POSSIBLE FUNDS from the HDD !!!!"
    echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
    read key

    echo "stopping services ... (please wait)"
    echo "- swap"
    sudo dphys-swapfile swapoff
    echo "- background"
    sudo systemctl stop background 2>/dev/null
    echo "- lnd"
    sudo systemctl stop lnd.service 2>/dev/null
    echo "- blockchain"
    sudo systemctl stop bitcoind.service 2>/dev/null
    sudo systemctl stop litecoind.service 2>/dev/null

    # delete plain all on HDD
    echo "cleaning HDD ... (please wait)"
    sudo rm -rfv /mnt/hdd/*

elif [ "${extraParameter}" = "-blockchain" ]; then

    if [ "${forceParameter}" != "-force" ]; then
      echo "This will DELETE JUST your blockchain from the HDD."
      echo "--> It will keep your LND data and other setups."
      echo "--> You will get presented re-download options."
      echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
      read key
    fi

    echo "stopping services ... (please wait)"
    echo "- swap"
    sudo dphys-swapfile swapoff
    echo "- background"
    sudo systemctl stop background 2>/dev/null
    echo "- lnd"
    sudo systemctl stop lnd.service 2>/dev/null
    echo "- blockchain"
    sudo systemctl stop bitcoind.service 2>/dev/null
    sudo systemctl stop litecoind.service 2>/dev/null
    echo ""
    echo "DELETING ..."
    sudo rm -f -r /mnt/hdd/bitcoin/blocks 2>/dev/null
    sudo rm -f -r /mnt/hdd/bitcoin/chainstate 2>/dev/null
    sudo rm -f -r /mnt/hdd/litecoin/blocks 2>/dev/null
    sudo rm -f -r /mnt/hdd/litecoin/chainstate 2>/dev/null

    echo "OK Blockchain data deleted - you may want now run: /home/admin/98repairBlockchain.sh"
    
else

    echo "!!!! This will DELETE your personal data & POSSIBLE FUNDS from the HDD !!!!"
    echo "--> It will keep Blockchain data - so you dont have to download/copy again."
    echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
    read key

    echo "stopping services ... (please wait)"
    echo "- swap"
    sudo dphys-swapfile swapoff
    echo "- background"
    sudo systemctl stop background 2>/dev/null
    echo "- lnd"
    sudo systemctl stop lnd.service 2>/dev/null
    echo "- blockchain"
    sudo systemctl stop bitcoind.service 2>/dev/null
    sudo systemctl stop litecoind.service 2>/dev/null

    # just delete selective
    echo "selective delete ... (please wait)"
    sudo rm -f -r /mnt/hdd/backup_lnd
    sudo rm -f -r /mnt/hdd/lnd
    sudo rm -f -r /mnt/hdd/ssh
    sudo rm -f /mnt/hdd/swapfile
    sudo rm -f /mnt/hdd/bitcoin/bitcoin.conf
    sudo rm -f /mnt/hdd/bitcoin/bitcoin.pid
    sudo rm -f /mnt/hdd/bitcoin/*.dat
    sudo rm -f /mnt/hdd/bitcoin/*.log
    sudo rm -f /mnt/hdd/bitcoin/*.pid
    sudo rm -f /mnt/hdd/bitcoin/testnet3/*.dat
    sudo rm -f /mnt/hdd/bitcoin/testnet3/*.log
    sudo rm -f /mnt/hdd/bitcoin/testnet3/.lock
    sudo rm -f /mnt/hdd/litecoin/litecoin.conf
    sudo rm -f /mnt/hdd/litecoin/litecoin.pid
    sudo rm -f /mnt/hdd/litecoin/*.dat
    sudo rm -f /mnt/hdd/litecoin/*.log
    sudo rm -f /mnt/hdd/litecoin/*.pid
    sudo rm -f -r /mnt/hdd/lost+found
    sudo rm -f -r /mnt/hdd/download
    sudo rm -f -r /mnt/hdd/tor
    sudo rm -f -r /mnt/hdd/temp
    sudo rm -f -r /mnt/hdd/backup_lnd
    sudo rm -f /mnt/hdd/raspiblitz.conf
    sudo rm -f /home/admin/raspiblitz.info
    

fi

echo "*************************"
echo "OK - the HDD is now clean"
echo "*************************"
echo "reboot -> sudo shutdown -r now"
echo "power off -> sudo shutdown now"
