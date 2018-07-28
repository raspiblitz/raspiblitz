echo ""

# load network
network=`cat .network`

echo "!!!! This will DELETE your personal data from the HDD !!!!"
echo "--> use the HDD with just blockchain in a fresh setup"
echo "Press ENTER to continue - CTRL+c to CANCEL"
read key
sudo dphys-swapfile swapoff
sudo systemctl stop ${network}d.service
sudo systemctl stop lnd.service
sudo rm -f -r /mnt/hdd/lnd
sudo rm -f /mnt/hdd/swapfile
sudo rm -f /mnt/hdd/${network}/${network}.conf
sudo rm -f /mnt/hdd/${network}/${network}.pid
sudo rm -f /mnt/hdd/${network}/*.dat
sudo rm -f /mnt/hdd/${network}/*.log
sudo rm -f /mnt/hdd/${network}/testnet3/*.dat
sudo rm -f /mnt/hdd/${network}/testnet3/*.log
sudo rm -f /mnt/hdd/${network}/testnet3/.lock
sudo rm -f -r /mnt/hdd/${network}/database
sudo chown admin:admin -R /mnt/hdd/${network}
echo "1" > /home/admin/.setup
echo "OK - the HDD is now clean"
