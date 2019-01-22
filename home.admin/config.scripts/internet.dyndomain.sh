#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a dynamic domain like freeDNS"
 echo "internet.dyndomain.sh [on|off] [?domainName] [?updateURL]"
 exit 1
fi

# 1. parameter [on|off]
turn="off"
if [ "$1" = "1" ] || [ "$1" = "on" ]; then turn="on"; fi

# 2. parameter [?domainName]
dynDomain=$2

# 3. parameter [?domainName]
updateDynDomain=$3

# run interactive if 'turn on' && no further parameters
if [ "${turn}" = "on" ] && [ ${#dynDomain} -eq 0 ]; then

  dialog --backtitle "DynamicDNS" --inputbox "ENTER the Dynamic Domain Name:

For more details see chapter in GitHub README 
'Public Domain with DynamicDNS'
https://github.com/rootzoll/raspiblitz

example: freedns.afraid.org
" 13 52 2>./.tmp
  dynDomain=$( cat ./.tmp )
  if [ ${#dynDomain} -eq 0 ]; then
    echo "FAIL input cannot be empty"
    exit 1
  fi

  dialog --backtitle "DynamicDNS" --inputbox "OPTIONAL Public IP Update URL:

The RaspiBlitz will call this URL regularly.
4 service freedns.afraid.org use 'DirectURL' 
" 10 52 2>./.tmp
  dynUpdateUrl=$( cat ./.tmp )
  shred ./.tmp

fi

# config file
configFile="/mnt/hdd/raspiblitz.conf"

# lnd conf file
lndConfig="/mnt/hdd/lnd/lnd.conf"

# check if config file exists
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
 echo "FAIL - missing ${configFile}"
 exit 1
fi

# make sure entry line for 'dynDomain' exists 
entryExists=$(cat ${configFile} | grep -c 'dynDomain=')
if [ ${entryExists} -eq 0 ]; then
  echo "dynDomain=" >> ${configFile}
fi

# make sure entry line for 'dynUpdateUrl' exists 
entryExists=$(cat ${configFile} | grep -c 'dynUpdateUrl')
if [ ${entryExists} -eq 0 ]; then
  echo "dynUpdateUrl=" >> ${configFile}
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the DynamicDNS ON"
  echo "dynDomain(${dynDomain})"
  echo "dynUpdateUrl(${dynUpdateUrl})"

  # setting value in raspi blitz config
  sudo sed -i "s/^dynDomain=.*/dynDomain='${dynDomain}'/g" /mnt/hdd/raspiblitz.conf
  sudo sed -i "s/^dynUpdateUrl=.*/dynUpdateUrl='${dynUpdateUrl}'/g" /mnt/hdd/raspiblitz.conf

  echo "changing lnd.conf"

  # lnd.conf: uncomment tlsextradomain (just if it is still uncommented)
  sudo sed -i "s/^#tlsextradomain=.*/tlsextradomain=/g" /mnt/hdd/lnd/lnd.conf

  # lnd.conf: domain value
  sudo sed -i "s/^tlsextradomain=.*/tlsextradomain=${dynDomain}/g" /mnt/hdd/lnd/lnd.conf

  echo "DynamicDNS is now ON"
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching DynamicDNS OFF"

  # setting value in raspi blitz config
  sudo sed -i "s/^dynDomain=.*/dynDomain=/g" /mnt/hdd/raspiblitz.conf
  sudo sed -i "s/^dynUpdateUrl=.*/dynUpdateUrl=/g" /mnt/hdd/raspiblitz.conf

  echo "changing lnd.conf"

  # lnd.conf: comment tlsextradomain out
  sudo sed -i "s/^tlsextradomain=.*/#tlsextradomain=/g" /mnt/hdd/lnd/lnd.conf

  echo "DynamicDNS is now OFF"
fi

# refresh TLS cert
sudo /home/admin/config.scripts/lnd.newtlscert.sh

echo "may needs reboot to run normal again"
exit 0