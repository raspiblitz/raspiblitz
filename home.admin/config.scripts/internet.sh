#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# handle the internet connection"
 echo "# internet.sh status [local|global]"
 echo "# internet.sh ipv6 [on|off]"
 echo "# internet.sh update-publicip [?domain]"
 exit 1
fi

# check when to global check
runGlobal=0
if [ "$2" == "global" ]; then
  runGlobal=1
fi
if [ "$1" == "update-publicip" ]; then
  runGlobal=1
fi

# load local config (but should also work if not available)
source /mnt/hdd/raspiblitz.conf 2>/dev/null

#############################################
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

#############################################
# by deafult ipv6 is off (for publicIP)
if [ "${ipv6}" = "" ]; then
  ipv6="off"
fi

#############################################
# get active network device (eth0 or wlan0) & trafiic
networkDevice=$(ip addr | grep -v "lo:" | grep 'state UP' | tr -d " " | cut -d ":" -f2 | head -n 1)
# get network traffic
# ifconfig does not show eth0 on Armbian or in a VM - get first traffic info
isArmbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
if [ ${isArmbian} -gt 0 ] || [ ! -d "/sys/class/thermal/thermal_zone0/" ]; then
  network_rx=$(ifconfig | grep -m1 'RX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')
  network_tx=$(ifconfig | grep -m1 'TX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')
else
  network_rx=$(ifconfig ${networkDevice} | grep 'RX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')
  network_tx=$(ifconfig ${networkDevice} | grep 'TX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')
fi

#############################################
# get local IP (from different sources)
localip_ALL=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | egrep -i '(*[eth|ens|enp|eno|wlan|wlp][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
if [ $(isValidIP ${localip_ALL}) -eq 0 ]; then
  localip_ALL=""
fi
localip_LAN=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | egrep -i '(*[eth][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
if [ $(isValidIP ${localip_LAN}) -eq 0 ]; then
  localip_LAN=""
fi
localip="${localip_ALL}"
if [ ${#localip_LAN} -gt 0 ]; then
  # prefer local IP over LAN over all other if available
  localip="${localip_LAN}"
fi

#############################################
# check DHCP
dhcp=1
if [ "${localip:0:4}" = "169." ]; then
 dhcp=0
fi

#############################################
# check for internet connection
online=0
if [ ${#dnsServer} -gt 0 ]; then
  # re-test with user set dns server
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
  # re-test with other server (IPv6)
  online=$(ping 2620:119:35::35 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 208.67.222.222 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server (IPv6)
  online=$(ping 2001:4860:4860::8844 -c 1 -W 2 | grep -c '1 received')
fi
if [ ${online} -eq 0 ]; then
  # re-test with other server
  online=$(ping 1.1.1.1 -c 1 -W 2 | grep -c '1 received')
fi

#############################################
# check for internet connection
if [ ${runGlobal} -eq 1 ]; then

  ###########################################
  # Global IP
  # the public IP that can be detected from outside
  if [ "${ipv6}" == "on" ]; then
    globalIP=$(curl -s http://v6.ipv6-test.com/api/myip.php 2>/dev/null)
  else
    globalIP=$(curl -s http://v4.ipv6-test.com/api/myip.php 2>/dev/null)
  fi
  # prevent having no publicIP set at all and LND getting stuck
  # https://github.com/rootzoll/raspiblitz/issues/312#issuecomment-462675101
  if [ ${#globalIP} -eq 0 ]; then
    if [ "${ipv6}" == "on" ]; then
      globalIP="::1"
    else
      globalIP="127.0.0.1"
    fi
  fi

  ##########################################
  # Public IP
  # the public that is maybe set by raspibitz config file (overriding aut-detection)
  if [ "${publicIP}" == "" ]; then
    # if publicIP is not set by config ... use detected global IP
    if [ "${ipv6}" == "on" ]; then
      # use ipv6 with brackes so that it can be used in http addresses like a IPv4
      publicIP="[${globalIP}]"
    else
      publicIP="${globalIP}"
    fi
  fi

  ##########################################
  # Clean IP
  # really just the IP value - without the default brackets if IPv6
  # for IPV4 case the "tr" will do no harm.
  cleanIP=$(echo "${publicIP}" | tr -d '[]')

fi

#############################################
if [ "$1" == "status" ]; then

  echo "### LOCAL INTERNET ###"
  echo "localip=${localip}"
  echo "dhcp=${dhcp}"
  echo "network_device=${networkDevice}"
  echo "network_rx='${network_rx}'"
  echo "network_tx='${network_tx}'"
  echo "### GLOBAL INTERNET ###"
  echo "online=${online}"
  if [ ${runGlobal} -eq 1 ]; then
    echo "ipv6=${ipv6}"
     echo "# globalip --> ip detected from the outside"   
    echo "globalip=${globalIP}"
    echo "# publicip --> may consider the static IP overide by raspiblitz config"
    echo "publicip=${publicIP}"
    echo "# cleanip --> the publicip with no brakets like used on IPv6"
    echo "cleanip=${cleanIP}"
  else
    echo "# for more global internet info use 'status global'"
  fi
  exit 0

#############################################
elif [ "$1" == "update-publicip" ]; then

  if [ "$2" != "" ]; then
    echo "ip_changed=0"
    publicIP="$2"
  elif  [ "${globalIP}" == "${cleanIP}" ]; then
    echo "ip_changed=0"
    exit 0
  else
    echo "ip_changed=1"
    if [ "${ipv6}" == "on" ]; then
      # use ipv6 with brackes so that it can be used in http addresses like a IPv4
      publicIP="[${globalIP}]"
    else
      publicIP="${globalIP}"
    fi
    echo "publicip=${publicIP}"
  fi

  # store to raspiblitz.conf new publiciP
  publicIPValueExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c 'publicIP=')
  if [ ${publicIPValueExists} -gt 1 ]; then 
    # more then one publiIp entry - removing one
    sudo sed -i "s/^publicIP=.*//g" /mnt/hdd/raspiblitz.conf
  fi
  if [ ${publicIPValueExists} -eq 0 ]; then
    echo "publicIP='${publicIP}'" >> /mnt/hdd/raspiblitz.conf
  else
    sudo sed -i "s/^publicIP=.*/publicIP='${publicIP}'/g" /mnt/hdd/raspiblitz.conf
  fi
  exit 0

#############################################
elif [ "$1" == "ipv6" ]; then

  if [ "$2" == "on" ]; then

    echo "# Switching IPv6 ON"

    # set config
    if ! grep -Eq "^ipv6=" /mnt/hdd/raspiblitz.conf; then
      echo "ipv6=on" >> /mnt/hdd/raspiblitz.conf
    else
      sudo sed -i "s/^ipv6=.*/ipv6=on/g" /mnt/hdd/raspiblitz.conf
    fi
    exit 0

  elif [ "$2" == "off" ]; then

    echo "# Switching IPv6 OFF"

    # set config
    sudo sed -i "s/^ipv6=.*/ipv6=off/g" /mnt/hdd/raspiblitz.conf
    exit 0

  else
    echo "error='unknown second parameter'"
    exit 1
  fi

else
  echo "err='parameter not known - run with -help'"
fi
