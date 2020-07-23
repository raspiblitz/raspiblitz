#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# handle the internet connection"
 echo "# internet.sh status"
 exit 1
fi

# load local config
source /mnt/hdd/raspiblitz.conf

# get local IP
localip_ALL=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | egrep -i '(*[eth|ens|enp|eno|wlan|wlp][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
localip_LAN=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | egrep -i '(*[eth][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
localip="${localip_ALL}"
if [ ${#localip_LAN} -gt 0 ]; then
  # prefer local IP over LAN over all other if available
  localip="${localip_LAN}"
fi

# check for internet connection
online=0
if [ ${#dnsServer} -gt 0 ]; then
  # re-test with other server
  online=$(ping ${dnsServer} -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 1.0.0.1 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 8.8.8.8 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 208.67.222.222 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 1.1.1.1 -c 1 -W 2 | grep -c '1 received')
fi

if [ "$1" == "status" ]; then

  echo "localip=${localip}"
  echo "online=${online}"
  exit 0

else
  echo "err='parameter not known - run with -help'"
fi
