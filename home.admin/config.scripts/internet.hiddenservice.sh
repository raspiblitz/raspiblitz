#!/bin/bash
# $1 is the service name, same as the HiddenServiceDir in torrc
# $2 is the port the Hidden Service forwards to (to be used in the Tor browser)
# $3 is the port to be forwarded with the Hidden Service

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to configure a Tor Hidden Service"
 echo "internet.hiddenservice.sh [service] [toPort] [fromPort] [optional-toPort2] [optional-fromPort2]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

service="$1"
if [ ${#service} -eq 0 ]; then
  echo "ERROR: service name is missing"
  exit 1
fi

toPort="$2"
if [ ${#toPort} -eq 0 ]; then
  echo "ERROR: the port to forward to is missing"
  exit 1
fi

fromPort="$3"
if [ ${#fromPort} -eq 0 ]; then
  echo "ERROR:the port to forward from is missing"
  exit 1
fi

# not mandatory
toPort2="$4"

# needed if $4 is given
fromPort2="$5"
if [ ${#toPort2} -gt 0 ]; then
  if [ ${#fromPort2} -eq 0 ]; then
    echo "ERROR:the second port to forward from is missing"
    exit 1
  fi
fi

if [ "${runBehindTor}" = "on" ]; then
  #check if the service is already present
  isHiddenService=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c $service)
  if [ ${isHiddenService} -eq 0 ]; then
    #check if the port is already forwarded
    alreadyThere=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c 127.0.0.1:$fromPort)
    if [ ${alreadyThere} -gt 0 ]; then
      echo "The $fromPort is already forwarded. Check /etc/tor/torrc for the details"
      exit 1
    fi
    echo "
# Hidden Service for $service
HiddenServiceDir /mnt/hdd/tor/$service
HiddenServiceVersion 3
HiddenServicePort $toPort 127.0.0.1:$fromPort" | sudo tee -a /etc/tor/torrc

# check and insert second port pair
if [ ${#toPort2} -gt 0 ]; then
  alreadyThere=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c 127.0.0.1:$fromPort2)
  if [ ${alreadyThere} -gt 0 ]; then
    echo "The $fromPort2 is already forwarded. Check /etc/tor/torrc for the details"
  else
    echo "HiddenServicePort $toPort2 127.0.0.1:$fromPort2" | sudo tee -a /etc/tor/torrc
  fi
fi
    # restart tor
    echo "Restarting Tor to activate the Hidden Service..."
    sudo systemctl restart tor
    sleep 10
  else
    echo "The Hidden Service is already installed"
  fi
  # show the Hidden Service address
  TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/$service/hostname)
  if [ -z "$TOR_ADDRESS" ]; then
    echo "Waiting for the Hidden Service"
    sleep 10
    TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/$service/hostname)
    if [ -z "$TOR_ADDRESS" ]; then
      echo " FAIL - The Hidden Service address could not be found - Tor error?"
      exit 1
    fi
  fi
  echo "The Tor Hidden Service address for $service is:"
  echo "$TOR_ADDRESS"
  echo "use with the port: $toPort"
  if [ ${#toPort2} -gt 0 ] && [ ${alreadyThere} -eq 0 ]; then
    echo "or the port: $toPort2"
  fi
else
  echo "Tor is not active"
  exit 1
fi
