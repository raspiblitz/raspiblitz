#!/bin/bash
echo ""
extraParameter="$1"
forceParameter="$2"
if [ "${extraParameter}" = "-all" ]; then

    echo "# !!!! This will DELETE ALL DATA & POSSIBLE FUNDS from the HDD !!!!"
    echo "# Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
    read key

    echo "# stopping services ... (please wait)"
    echo "# - swap"
    sudo dphys-swapfile swapoff
    echo "# - background"
    sudo systemctl stop background 2>/dev/null
    echo "# - lnd"
    sudo systemctl stop lnd.service 2>/dev/null
    echo "# - blockchain"
    sudo systemctl stop bitcoind.service 2>/dev/null

    # delete plain all on HDD
    echo "# cleaning HDD ... (please wait)"
    sudo rm -rfv /mnt/hdd/*

elif [ "${extraParameter}" = "-blockchain" ]; then

    if [ "${forceParameter}" != "-force" ]; then
      echo "# This will DELETE JUST your blockchain from the HDD."
      echo "# --> It will keep your LND data and other setups."
      echo "# --> You will get presented re-download options."
      echo "# Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
      read key
    fi

    echo "# stopping services ... (please wait)"
    echo "# - lnd"
    sudo systemctl stop lnd.service 2>/dev/null
    echo "# - blockchain"
    sudo systemctl stop bitcoind.service 2>/dev/null
    echo ""
    echo "# DELETING ..."

    # delete bitcoin blockchain (but keep config & wallet)
    sudo mv /mnt/hdd/bitcoin/bitcoin.conf /mnt/hdd/bitcoin.conf 2>/dev/null
    sudo mv /mnt/hdd/bitcoin/wallet.dat /mnt/hdd/wallet.dat 2>/dev/null
    sudo rm -f -r /mnt/hdd/bitcoin/*
    sudo mv /mnt/hdd/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null
    sudo mv /mnt/hdd/wallet.dat /mnt/hdd/bitcoin/wallet.dat 2>/dev/null
    sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin

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

    # just delete selective
    echo "selective delete ... (please wait)"

    # bitcoin mainnet (clean working files)
    sudo rm -f /mnt/hdd/bitcoin/* 2>/dev/null
    sudo rm -f /mnt/hdd/bitcoin/.* 2>/dev/null
    sudo rm -f -r /mnt/hdd/bitcoin/database

    # bitcoin testnet (clean working files)
    sudo rm -f /mnt/hdd/bitcoin/testnet3/* 2>/dev/null
    sudo rm -f /mnt/hdd/bitcoin/testnet3/.* 2>/dev/null
    sudo rm -f -r /mnt/hdd/bitcoin/testnet/database

    # litecoin mainnet (clean working files) -- keep for legacy clean up reasons
    sudo rm -f /mnt/hdd/litecoin/* 2>/dev/null
    sudo rm -f /mnt/hdd/litecoin/.* 2>/dev/null
    sudo rm -f -r /mnt/hdd/litecoin/database

    # lnd (delete all)
    sudo rm -f -r /mnt/hdd/lnd
    sudo rm -f -r /mnt/hdd/backup_lnd

    # mixed other files and folders (all)
    sudo rm -f -r /mnt/hdd/lost+found
    sudo rm -f -r /mnt/hdd/download
    sudo rm -f -r /mnt/hdd/tor
    sudo rm -f -r /mnt/hdd/temp
    sudo rm -f -r /mnt/hdd/ssh
    sudo rm -f -r /mnt/hdd/app-storage
    sudo rm -f -r /mnt/hdd/app-data
    sudo rm -f /mnt/hdd/swapfile
    sudo rm -f /mnt/hdd/*.*

fi

echo "*************************"
echo "OK - the HDD is now clean"
echo "*************************"
echo "reboot -> sudo shutdown -r now"
echo "power off -> sudo shutdown now"
