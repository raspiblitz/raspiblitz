#!/bin/bash

echo 'getpublicip.sh started, writing public IP address every 10 minutes into /run/publicip'
while [ 0 ];
    do
    # check if TOR is running
    torExists=$(sudo ls /mnt/hdd/tor/lnd9735/hostname 2>/dev/null | grep hostname -c)
    if [ ${torExists} -eq 0 ]; then
      # get and set public IP
      printf "PUBLICIP=$(curl -vv ipinfo.io/ip 2> /run/publicip.log)\n" > /run/publicip;
    else
      # set onion address
      printf "PUBLICIP=$(sudo cat /mnt/hdd/tor/lnd9735/hostname)\n" > /run/publicip;
    fi
    sleep 600
done;