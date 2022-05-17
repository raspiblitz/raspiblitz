#!/bin/bash

# INFO : Does not need to be part of update/provision, because
# all data is already on HDD ready

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a fixed domain or IP for LND"
 echo "lnd.setaddress.sh [on|off] [?address]"
 exit 1
fi

# 1. parameter [on|off]
mode="$1"

# lnd conf file
lndConfig="/mnt/hdd/lnd/lnd.conf"

# get hash of lnd.conf before edit (to detect if changed later)
md5HashBefore=$(sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf)

# FIXED DOMAIN/IP
if [ "${mode}" = "on" ]; then

  address=$2
  if [ ${#address} -eq 0 ]; then
    echo "# missing parameter"
    exit 1
  fi

  echo "# switching fixed LND Domain ON"
  echo "# address(${address})"

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lndAddress "${address}"

  echo "# changing lnd.conf"

  # lnd.conf: uncomment tlsextradomain (just if it is still uncommented)
  sudo sed -i "s/^#tlsextradomain=.*/tlsextradomain=/g" /mnt/hdd/lnd/lnd.conf

  # lnd.conf: domain value
  sudo sed -i "s/^tlsextradomain=.*/tlsextradomain=${address}/g" /mnt/hdd/lnd/lnd.conf

  # refresh TLS cert
  md5HashAfter=$(sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf)
  if [ "${md5HashAfter}" != "${md5HashBefore}" ]; then
    echo "# lnd.conf changed - TLS certs need refreshing"
    sudo /home/admin/config.scripts/lnd.tlscert.sh refresh
  else
    echo "# lnd.conf NOT changed - keep TLS certs"
  fi

  echo "# fixedAddress is now ON"
fi

# switch off
if [ "${mode}" = "off" ]; then
  echo "# switching fixedAddress OFF"

  # stop services
  echo "# making sure services are not running"
  sudo systemctl stop lnd 2>/dev/null

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lndAddress ""

  echo "# changing lnd.conf"

  # lnd.conf: comment tlsextradomain out
  sudo sed -i "s/^tlsextradomain=.*/#tlsextradomain=/g" /mnt/hdd/lnd/lnd.conf

  # refresh TLS cert
  md5HashAfter=$(sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf)
  if [ "${md5HashAfter}" != "${md5HashBefore}" ]; then
    echo "# lnd.conf changed - TLS certs need refreshing"
    sudo /home/admin/config.scripts/lnd.tlscert.sh refresh
  else
    echo "# lnd.conf NOT changed - keep TLS certs"
  fi

  echo "# fixedAddress is now OFF"
fi

echo "# may needs reboot to run normal again"
exit 0
