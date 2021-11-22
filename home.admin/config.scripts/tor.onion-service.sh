#!/bin/bash
# $1 is the service name, same as the HiddenServiceDir in torrc
# $2 is the port the Hidden Service forwards to (to be used in the Tor browser)
# $3 is the port to be forwarded with the Hidden Service

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to configure a Tor Hidden Service"
 echo "tor.onion-service.sh [service] [toPort] [fromPort] [optional-toPort2] [optional-fromPort2]"
 echo "tor.onion-service.sh off [service]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

torrc_services="/etc/tor/torrc.d/services"

# delete a hidden service
if [ "$1" == "off" ]; then

  service="$2"
  if [ ${#service} -eq 0 ]; then
    echo "ERROR: service name is missing"
    exit 1
  fi

  # remove service paragraph
  sudo sed -i "/# Hidden Service for ${service}/,/^\s*$/{d}" "${torrc_services}"

  # remove double empty lines
  sudo cp "${torrc_services}" /var/cache/raspiblitz/tmp
  sudo chmod 777 /var/cache/raspiblitz/tmp
  sudo chown admin:admin /var/cache/raspiblitz/tmp
  sudo awk 'NF > 0 {blank=0} NF == 0 {blank++} blank < 2' "${torrc_services}" > /var/cache/raspiblitz/tmp
  sudo mv /var/cache/raspiblitz/tmp "${torrc_services}"
  sudo chmod 644 "${torrc_services}"
  sudo chown bitcoin:bitcoin "${torrc_services}"

  echo "# OK service is removed - reloading Tor ..."
  sudo systemctl reload tor@default
  sleep 10
  echo "# Done"
  exit 0
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

fromPort="$3"
if [ ${#fromPort} -eq 0 ]; then
  echo "ERROR: the port to forward from is missing"
  exit 1
fi

# not mandatory
toPort2="$4"

# needed if $4 is given
fromPort2="$5"
if [ ${#toPort2} -gt 0 ]; then
  if [ ${#fromPort2} -eq 0 ]; then
    echo "ERROR: the second port to forward from is missing"
    exit 1
  fi
fi

if [ "${runBehindTor}" = "on" ]; then

  # delete any old entry for that servive
  sudo sed -i "/# Hidden Service for ${service}/,/^\s*$/{d}" "${torrc_services}"

  # make new entry for that service
  echo "
# Hidden Service for $service
HiddenServiceDir /mnt/hdd/tor/$service
HiddenServiceVersion 3
HiddenServicePort $toPort 127.0.0.1:$fromPort" | sudo tee -a "${torrc_services}"

  # remove double empty lines
  awk 'NF > 0 {blank=0} NF == 0 {blank++} blank < 2' "${torrc_services}" | sudo tee /var/cache/raspiblitz/tmp >/dev/null && sudo mv /var/cache/raspiblitz/tmp "${torrc_services}"

  # check and insert second port pair
  if [ ${#toPort2} -gt 0 ]; then
    alreadyThere=$(sudo cat "${torrc_services}" 2>/dev/null | grep -c "\b127.0.0.1:$fromPort2\b")
    if [ ${alreadyThere} -gt 0 ]; then
      echo "The port $fromPort2 is already forwarded. Check the "${torrc_services}" for the details."
    else
      echo "HiddenServicePort $toPort2 127.0.0.1:$fromPort2" | sudo tee -a "${torrc_services}"
    fi
  fi

  # reload tor
  echo
  echo "Reloading Tor to activate the Hidden Service..."
  sudo chmod 644 "${torrc_services}"
  sudo systemctl reload tor@default
  sleep 10

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
  echo ""
  echo "The Tor Hidden Service address for $service is:"
  echo "$TOR_ADDRESS"
  echo "use with the port: $toPort"
  if [ ${#toPort2} -gt 0 ]; then
    wasAdded=$(sudo cat "${torrc_services}" 2>/dev/null | grep -c "\b127.0.0.1:$fromPort2\b")
    if [ ${wasAdded} -gt 0 ]; then
      echo "or the port: $toPort2"
    fi
  fi
else
  echo "Tor is not active"
  exit 1
fi
