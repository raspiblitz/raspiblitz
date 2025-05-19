#!/bin/bash
echo ""
extraParameter="$1"
forceParameter="$2"
if [ "${extraParameter}" = "-all" ]; then

    echo "## This will DELETE ALL DATA & POSSIBLE FUNDS from the HDD ##"
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
    sudo systemctl stop bitcoind.service 2>/dev/null

    echo "selective blockchain data ... (please wait)"

    # conf & wallet files are in /mnt/hdd/app-data/bitcoin - so delete all in storage
    sudo rm -r -f /mnt/hdd/app-storage/bitcoin/*
    sudo /home/admin/config.scripts/blitz.data.sh link

    echo "OK Blockchain data deleted, restart needed - you may want now run: /home/admin/98repairBlockchain.sh"
    
else

    echo "## This will DELETE your personal data & POSSIBLE FUNDS from the HDD ##"
    echo "--> It will keep Blockchain data - so you dont have to download/copy again."
    echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
    read key

    echo "stopping services ... (please wait)"
    sudo dphys-swapfile swapoff
    sudo systemctl stop background 2>/dev/null
    sudo systemctl stop bitcoind.service 2>/dev/null

    # just delete selective
    echo "selective delete ... (please wait)"

    # bitcoin mainnet (clean working files)
    sudo rm -f /mnt/hdd/app-storage/bitcoin/* 2>/dev/null
    sudo rm -f /mnt/hdd/app-storage/bitcoin/.* 2>/dev/null
    sudo rm -f -r /mnt/hdd/app-storage/bitcoin/indexes 2>/dev/null

    # delete all directories in /mnt/hdd/app-storage - but not the "bitcoin" folder
    sudo mv /mnt/hdd/app-storage/bitcoin /mnt/hdd/app-data/bitcoin-temp 2>/dev/null
    sudo rm -f -r /mnt/hdd/app-storage/* 2>/dev/null
    sudo mv /mnt/hdd/app-data/bitcoin-temp /mnt/hdd/app-storage/bitcoin 2>/dev/null

    # delete rest of all data
    sudo rm -f -r /mnt/hdd/hdd/app-data 2>/dev/null
    sudo rm -f -r /mnt/disk_storage/app-data 2>/dev/null
    sudo rm -f -r /mnt/disk_data/app-data 2>/dev/null
    sudo rm -f -r /mnt/disk_storage/temp 2>/dev/null
fi

echo "*************************"
echo "OK - the HDD is now clean"
echo "*************************"
echo "reboot -> sudo shutdown -r now"
echo "power off -> sudo shutdown now"
