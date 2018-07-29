#!/bin/sh

# *** BITCOIN Torrent ***
bitcoinTorrent="raspiblitz-bitcoin-2018-07-16"
bitcoinTorrentsize=231230512
                   
# *** LITECOIN Torrent ***
litecoinTorrent="raspiblitz-litecoin-2018-07-29"
litecoinTorrentsize=10240000

# load network
network=`cat .network`

# settings based on network
torrent=$bitcoinTorrent
torrentsize=$bitcoinTorrentsize
if [ "$network" = "litecoin" ]; then
  torrent=$litecoinTorrent
  torrentsize=$litecoinTorrentsize
fi
echo ""
echo "torrentFile: ${torrent}"

echo ""
echo "*** Downloading TORRENT ***"
echo "IN CASE DOWNLOAD DOES NOT START OR TOO SLOW:"
echo "CTRL+z start ./10setupBlitz.sh choose other option"
echo "***************************"
echo ""
tmpfile=$(mktemp)
chmod a+x $tmpfile
echo "killall transmission-cli" > $tmpfile
sudo transmission-cli ./assets/$torrent.torrent -D -et -w /mnt/hdd -f $tmpfile
echo "OK - Download closed"
echo ""

echo "*** Checking TORRENT ***"
echo "wait a moment"
sleep 5
downloadsize=$(sudo du -s /mnt/hdd/$torrent/ | awk '{print $1}' | tr -dc '0-9')
if [ ${#downloadsize} -eq 0 ]; then 
  downloadsize=0
fi
# add some tolerance for checking 
size="$(($size-1024000))"
echo "download size is(${downloadsize}) needs to be minimum(${size})"
if [ ${downloadsize} -lt ${size} ]; then
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING " --yesno "The download failed or is not complete. Do you want keep already downloaded data?" 6 57
  response=$?
  case $response in
    1) sudo rm -rf /mnt/hdd/$torrent ; sudo rm -rf /root/.config/transmission ;;
  esac
  ./00mainMenu.sh
  exit 1;
fi

echo "*** Moving Files ***"
echo "moving files ..."
sudo mv /mnt/hdd/$torrent /mnt/hdd/${network}
echo ""

# set SetupState
echo "50" > /home/admin/.setup

# continue setup
./60finishHDD.sh