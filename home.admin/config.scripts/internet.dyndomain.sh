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

echo "number of args($#)"

# 2. parameter [?domainName]
if [ $# > 1 ]; then
  dynDomain=$2
fi

# 3. parameter [?domainName]
if [ $# > 2 ]; then
  dynUpdateUrl=$3
fi

# run interactive if 'turn on' && no further parameters
if [ "${turn}" = "on" ] && [ ${#dynDomain} -eq 0 ]; then

  # make sure dialog file is writeable
  sudo touch ./.tmp
  sudo chmod 777 ./.tmp

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
  shred -u ./.tmp

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
  echo "# switching the DynamicDNS ON"
  echo "# dynDomain(${dynDomain})"
  echo "# dynUpdateUrl(${dynUpdateUrl})"

  # setting dynUpdateUrl is a bit complicated because value can contain chars that break sed replacement
  # so first remove dynUpdateUrl from config and then add fresh as new line at the end

  # remove line & write fresh
  sudo sed -i "/dynDomain=*/d" /mnt/hdd/raspiblitz.conf
  echo "dynDomain='${dynDomain}'" >> /mnt/hdd/raspiblitz.conf

  # remove line & write fresh
  sudo sed -i "/dynUpdateUrl=*/d" /mnt/hdd/raspiblitz.conf
  echo "dynUpdateUrl='${dynUpdateUrl}'" >> /mnt/hdd/raspiblitz.conf

  # lnd.conf: domain value &
  sudo /home/admin/config.scripts/lnd.tlscert.sh domain-add ${dynDomain}

  echo "# DynamicDNS is now ON"
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# switching DynamicDNS OFF"

  # setting value in raspi blitz config
  sudo sed -i "/dynUpdateUrl=*/d" /mnt/hdd/raspiblitz.conf
  sudo sed -i "/dynDomain=*/d" /mnt/hdd/raspiblitz.conf

  # lnd.conf: remove domain tls entries
  sudo /home/admin/config.scripts/lnd.tlscert.sh domain-remove ALL

  echo "# DynamicDNS is now OFF"
fi

# refresh TLS cert
sudo /home/admin/config.scripts/lnd.tlscert.sh refresh

echo "# may needs reboot to run normal again"
exit 0
