#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# handle the internet connection"
 echo "# internet.sh status"
 exit 1
fi

# FUNCTIONS

isValidIP() {
  if [ "$1" != "${1#*[0-9].[0-9]}" ]; then
    # IPv4
    echo 1
  elif [ "$1" != "${1#*:[0-9a-fA-F]}" ]; then
    # IPv6
    echo 1
  else
    # unkown
    echo 0
  fi
}

# load local config (but should also work if not available)
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# get local IP (from different sources)
localip_ALL=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | egrep -i '(*[eth|ens|enp|eno|wlan|wlp][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
if [ $(isValidIP ${localip_ALL}) -eq 0 ]; then
  localip_ALL=""
fi
localip_LAN=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | egrep -i '(*[eth][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
if [ $(isValidIP ${localip_LAN}) -eq 0 ]; then
  localip_LAN=""
fi
localip="${localip_ALL}"
if [ ${#localip_LAN} -gt 0 ]; then
  # prefer local IP over LAN over all other if available
  localip="${localip_LAN}"
fi

# check DHCP
dhcp=1
if [ "${localip:0:4}" = "169." ]; then
 dhcp=0
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
  echo "dhcp=${dhcp}"
  echo "online=${online}"
  exit 0

else
  echo "err='parameter not known - run with -help'"
fi
