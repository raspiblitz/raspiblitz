#!/bin/bash
# RaspiBolt LND Mainnet: script to get public ip address
# /usr/local/bin/getpublicip.sh

echo 'getpublicip.sh started, writing public IP address every 10 minutes into /run/publicip'
while [ 0 ];
    do
    # when TOR is installed the fixed onion address is already in /run/publicip
    torExists=$(sudo ls /mnt/hdd/tor/web80/hostname 2>/dev/null | grep hostname -c)
    if [ ${torExists} -eq 0 ]; then
      # get public IP
      printf "PUBLICIP=$(curl -vv ipinfo.io/ip 2> /run/publicip.log)\n" > /run/publicip;
    fi
    sleep 600
done;