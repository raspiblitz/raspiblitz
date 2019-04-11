#!/bin/bash
echo ""
extraParameter="$1"
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

else

    echo "!!!! This will DELETE your personal data & POSSIBLE FUNDS from the HDD !!!!"
    echo "--> It will keep Blockchain data - so you dont have to download/copy again."
    echo "--> If you want to delete also blockchain data, please run with '-all' parameter."
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
    sudo rm -f /mnt/hdd/raspiblitz.conf
    sudo rm -f /home/admin/raspiblitz.info
    

fi

echo "*************************"
echo "OK - the HDD is now clean"
echo "*************************"
echo "reboot -> sudo shutdown -r now"
echo "power off -> sudo shutdown now"
