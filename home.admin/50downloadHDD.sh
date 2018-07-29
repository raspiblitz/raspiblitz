#!/bin/sh
echo ""

# *** BITCOIN ***
bitcoinList="" # url to list with other sources
bitcoinUrl="ftp://anonymous:anonymous@tll9xsfkjht8j26z.myfritz.net/raspiblitz-bitcoin-2018-07-16"
bitcoinSize=100

# *** LITECOIN ***
litecoinList="" # url to list with other sources
litecoinUrl="ftp://anonymous:anonymous@ftp.rotzoll.de/pub/raspiblitz-litecoin-2018-07-29"
litecoinSize=19184980

# load network
network=`cat .network`

# settings based on network
list=$bitcoinList
url=$bitcoinUrl
size=$bitcoinSize
if [ "$network" = "litecoin" ]; then
  list=$litecoinList
  url=$litecoinUrl
  size=$litecoinSize
fi

# the path wget will download to
targetPath=$(echo ${url} | cut -d '@' -f2)

echo "network($network)"
echo "list($list)"
echo "url($url)"
echo "size($size)"
echo "targetPath($targetPath)"
echo ""

echo "*** Downloading HDD / FTP ***"
sudo wget -r -P /mnt/hdd/ -q --show-progress ${url}
echo "OK"
echo ""

echo "*** Checking Download ***"
downloadsize=$(sudo du -s /mnt/hdd/${targetPath} | awk '{print $1}' | tr -dc '0-9')
if [ ${#downloadsize} -eq 0 ]; then 
  downloadsize=0
fi
echo "download size is(${downloadsize}) needs to be minimum(${size}})"
if [ ${downloadsize} -lt ${size} ]; then
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING " --yesno "The download failed or is not complete. Do you want keep already downloaded data?" 6 57
  response=$?
  case $response in
    1) sudo rm -rf /mnt/hdd/${targetPath} ;;
  esac
  ./00mainMenu.sh
  exit 1;
fi
echo ""

echo "*** Moving Files ***"
sudo mv /mnt/hdd/${targetPath} /mnt/hdd/${network}
echo "OK"

# continue setup
./60finishHDD.sh