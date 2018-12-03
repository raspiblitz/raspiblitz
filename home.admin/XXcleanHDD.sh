echo ""

# load network
network=`cat .network`

echo "!!!! This will DELETE your data & POSSIBLE FUNDS from the HDD !!!!"
echo "Press ENTER to really continue - CTRL+c to CANCEL (last chance)"
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
sudo rm -f /mnt/hdd/${network}/*.pid
sudo rm -f /mnt/hdd/${network}/testnet3/*.dat
sudo rm -f /mnt/hdd/${network}/testnet3/*.log
sudo rm -f /mnt/hdd/${network}/testnet3/.lock
sudo rm -f -r /mnt/hdd/${network}/database
sudo rm -f -r /mnt/hdd/lost+found
sudo rm -f -r /mnt/hdd/download
sudo rm -f -r /mnt/hdd/tor
sudo rm -f /mnt/hdd/raspiblitz.conf
sudo chown admin:admin -R /mnt/hdd/${network}
echo "1" > /home/admin/.setup
echo "OK - the HDD is now clean"
