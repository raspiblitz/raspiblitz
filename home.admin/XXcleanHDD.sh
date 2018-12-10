echo ""
echo "!!!! This will DELETE your data & POSSIBLE FUNDS from the HDD !!!!"
echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
read key
sudo dphys-swapfile swapoff
sudo systemctl stop bitcoind.service 2>/dev/null
sudo systemctl stop litecoind.service 2>/dev/null
sudo systemctl stop lnd.service 2>/dev/null
sudo rm -f -r /mnt/hdd/lnd
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
echo "OK - the HDD is now clean"
