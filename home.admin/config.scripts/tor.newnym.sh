#!/bin/bash

service=${1}
if [ "${service}" = "" ]; then
  echo "Service cannot be blank"
  exit 0
fi

if [ "${service}" = "bitcoin" ]; then
  port=9050
  controlPort=9051
elif [ "${service}" = "lnd" ]; then
  port=9070
  controlPort=9071
elif [ "${service}" = "cln" ]; then
  port=9090
  controlPort=9091
else
  echo "Invalid service ${1}"
fi

oldID=$(curl --connect-timeout 15 --socks5-hostname localhost:${port} https://check.torproject.org 2>/dev/null | grep "Your IP address appears to be:")

echo "Requesting new identity..."
sudo python3 new_ident.py "${controlPort}"

sleep 3

newID=$(curl --connect-timeout 15 --socks5-hostname localhost:${port} https://check.torproject.org 2>/dev/null | grep "Your IP address appears to be:")

echo
if [ ${oldID} = ${newID} ]; then
  echo "Fail !!!: Identity for ${service} did not change. Read error message above."
else
  echo "Success !!!: Identity for ${service} did change"
  echo "Old id: "${oldID}
  echo "New id: "${newID}
fi