#!/bin/bash

# based on: https://github.com/rootzoll/raspiblitz/issues/100#issuecomment-465997126
# based on: https://github.com/rootzoll/raspiblitz/issues/386

if [ $# -eq 0 ]; then
 echo "script set the port LND is running on"
 echo "lnd.setport.sh [portnumber]"
 exit 1
fi

portnumber=$1

# check port number is a integer
if ! [ "$portnumber" -eq "$portnumber" ] 2> /dev/null
then
  echo "FAIL - portnumber(${portnumber}) not a number"
  exit 1
fi

# check port number is bigger then zero
if [ ${portnumber} -lt 1 ]; then
  echo "FAIL - portnumber(${portnumber}) not above 0"
  exit 1
fi

# check port number is smaller than max
if [ ${portnumber} -gt 65535 ]; then
  echo "FAIL - portnumber(${portnumber}) not below 65535"
  exit 1
fi

# check if TOR is on
source /mnt/hdd/raspiblitz.conf
if [ "${runBehindTor}" = "on" ]; then
  echo "FAIL - portnumber cannot be changed if TOR is ON (not implemented)"
  exit 1
fi

# add to raspiblitz.config (so it can survive update)
valueExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c 'lndPort=')
if [ ${valueExists} -eq 0 ]; then
  # add as new value
  echo "lndPort=${portnumber}" | tee -a  /mnt/hdd/raspiblitz.conf
else
  # update existing value
  sudo sed -i "s/^lndPort=.*/lndPort=${portnumber}/g" /mnt/hdd/raspiblitz.conf
fi

# enable service again
echo "enable service again"
sudo systemctl restart lnd

# make sure port is open on firewall
sudo ufw allow ${portnumber} comment 'LND Port'

echo "needs reboot to activate new setting -> sudo shutdown -r now"