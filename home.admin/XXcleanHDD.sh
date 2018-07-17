echo ""
echo "!!!! This will DELETE your personal data from the HDD !!!!"
echo "--> use the HDD with just blockchain in a fresh setup"
echo "Press ENTER to continue - CTRL+c to CANCEL"
read key
sudo dphys-swapfile swapoff
sudo systemctl stop bitcoind.service
sudo systemctl stop lnd.service
sudo rm -f -r /mnt/hdd/lnd
sudo rm -f /mnt/hdd/swapfile
sudo rm -f /mnt/hdd/bitcoin/bitcoin.conf
sudo rm -f /mnt/hdd/bitcoin/bitcoin.pid
sudo rm -f /mnt/hdd/bitcoin/*.dat
sudo rm -f /mnt/hdd/bitcoin/*.log
sudo rm -f /mnt/hdd/bitcoin/bitcoin.conf
sudo rm -f /mnt/hdd/bitcoin/testnet3/*.dat
sudo rm -f /mnt/hdd/bitcoin/testnet3/*.log
sudo rm -f /mnt/hdd/bitcoin/testnet3/.lock
sudo rm -f -r /mnt/hdd/bitcoin/database
sudo chown admin:admin -R /mnt/hdd/bitcoin
echo "1" > /home/admin/.setup
echo "OK - the HDD is now clean"
