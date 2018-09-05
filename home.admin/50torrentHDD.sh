#!/bin/bash
echo ""

# *** BITCOIN Torrent ***
bitcoinTorrent="raspiblitz-bitcoin-2018-07-16"
                   
# *** LITECOIN Torrent ***
litecoinTorrent="raspiblitz-litecoin-2018-07-29"

# load network
network=`cat .network`

targetDir="/mnt/hdd/torrent/"

# settings based on network
torrent=$bitcoinTorrent
if [ "$network" = "litecoin" ]; then
  torrent=$litecoinTorrent
fi

sudo apt-get install lftp -y
echo ""

# check if lftp is running in background
pid=$(pgrep lftp | head -n 1)
echo "${pid}"
if [ ${#pid} -eq 0 ]; then
  echo "Starting lftp"
  sudo mkdir ${targetDir} 2>/dev/null
  sudo lftp -c "torrent -O ${targetDir} /home/admin/assets/${torrent}.torrent; bye"
else
  echo "Reattaching lftp (${pid})"
  sudo lftp -c "attach ${pid}"
fi

exit 1

# TODO check success by size

# the path the actual data will be in
#targetPath="${targetDir}${torrent}"
#echo "path to downloaded data is ${targetPath}"

# calculate progress and write it to file for LCD to read
#finalSize=$( du -s ${targetDir} 2>/dev/null | head -n1 | awk '{print $1;}' )
#if [ ${#finalSize} -eq 0 ]; then
#  finalSize=0
#fi
#echo "final size is ${finalSize} of targeted size ${targetSize}"

# check result
#if [ ${finalSize} -lt ${targetSize} ]; then
 
 # Download failed
#  sleep 3
#  echo -ne '\007'
#  dialog --title " WARNING " --yesno "The download failed or is not complete. Maybe try again (later). Do you want keep already downloaded data for next try?" 8 57
#  response=$?
#  case $response in
#    1) sudo rm -rf ${targetDir} ;;
#  esac
#  ./00mainMenu.sh
#  exit 1;
#  
#else

#  # Download worked
#  echo "*** Moving Files ***"
#  sudo mv ${targetDir}${targetPath} /mnt/hdd/${network}
#  echo "OK"

  # continue setup
#  ./60finishHDD.sh