#!/bin/bash
# $1 is the service name, same as the HiddenServiceDir in torrc
# $2 is the port the Hidden Service forwards to (to be used in the Tor browser)
# S3 is the port to be forwarded with the Hidden Service

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to configure a Tor Hidden Service"
 echo "internet.hiddenservice.sh [service] [toPort] [fromPort]"
 exit 1
fi

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

fromPort="$2"
if [ ${#fromPort} -eq 0 ]; then
  echo "ERROR:the port to forward from is missing"
  exit 1
fi

isHiddenService=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c $service)
if [ ${isHiddenService} -eq 0 ]; then
  echo "
# Hidden Service for $service
HiddenServiceDir /mnt/hdd/tor/$service
HiddenServiceVersion 3
HiddenServicePort $toPort 127.0.0.1:$fromPort
" | sudo tee -a /etc/tor/torrc
  echo "Restarting Tor to activate the Hidden Service..."
  sudo systemctl restart tor
  sleep 10
else
  echo "The Hidden Service is already installed"
fi